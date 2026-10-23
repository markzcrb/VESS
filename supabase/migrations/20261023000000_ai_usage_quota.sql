-- VESS · daily AI quota per user (state as deployed on project "vess", ysiuljqenyugxrwmajmo).
-- No health data, prompts or photos are stored anywhere. Only a per-day counter.

create table public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null default (now() at time zone 'utc')::date,
  kind text not null check (kind in ('coach','photo')),
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day, kind)
);
alter table public.ai_usage enable row level security;

create policy "read own usage" on public.ai_usage
  for select to authenticated using ((select auth.uid()) = user_id);
-- No insert/update/delete policies: rows change only through the server-only functions below.

create or replace function public.ai_daily_limit(p_kind text)
returns integer language sql immutable set search_path = '' as $$
  select case p_kind when 'coach' then 20 when 'photo' then 10 else 0 end;
$$;
revoke all on function public.ai_daily_limit(text) from public, anon;
grant execute on function public.ai_daily_limit(text) to authenticated;

-- Consumes one unit; returns remaining for today, or -1 when the limit is reached.
create or replace function public.consume_ai_quota(p_user uuid, p_kind text)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  lim integer := public.ai_daily_limit(p_kind);
  used integer;
begin
  if p_user is null then raise exception 'no user'; end if;
  if lim = 0 then raise exception 'unknown kind'; end if;
  insert into public.ai_usage (user_id, day, kind, count)
  values (p_user, (now() at time zone 'utc')::date, p_kind, 1)
  on conflict (user_id, day, kind) do update set count = public.ai_usage.count + 1
    where public.ai_usage.count < lim
  returning count into used;
  if used is null then return -1; end if;
  return lim - used;
end $$;

-- Gives one unit back when the AI call failed.
create or replace function public.refund_ai_quota(p_user uuid, p_kind text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.ai_usage set count = greatest(count - 1, 0)
  where user_id = p_user and day = (now() at time zone 'utc')::date and kind = p_kind;
end $$;

-- Server only (edge functions use the service role). Users can't refund themselves.
revoke all on function public.consume_ai_quota(uuid, text) from public, anon, authenticated;
revoke all on function public.refund_ai_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.consume_ai_quota(uuid, text) to service_role;
grant execute on function public.refund_ai_quota(uuid, text) to service_role;
