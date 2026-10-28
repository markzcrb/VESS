-- Wallet protection: a project-wide daily cap on AI calls, on top of the per-user caps.
-- consume_ai_quota returns: remaining (>= 0), -1 user's daily limit reached, -2 global cap reached (edge functions answer 503 service_busy).
create table if not exists public.ai_usage_global (
  day date primary key default (now() at time zone 'utc')::date,
  count integer not null default 0 check (count >= 0)
);
alter table public.ai_usage_global enable row level security;
revoke all on public.ai_usage_global from anon, authenticated;

create or replace function public.ai_global_daily_limit()
returns integer language sql immutable set search_path = '' as $$ select 5000; $$;
revoke all on function public.ai_global_daily_limit() from public, anon, authenticated;

create or replace function public.consume_ai_quota(p_user uuid, p_kind text)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  lim integer := public.ai_daily_limit(p_kind);
  used integer;
  g integer;
begin
  if p_user is null then raise exception 'no user'; end if;
  if lim = 0 then raise exception 'unknown kind'; end if;
  insert into public.ai_usage_global (day, count) values ((now() at time zone 'utc')::date, 1)
  on conflict (day) do update set count = public.ai_usage_global.count + 1
    where public.ai_usage_global.count < public.ai_global_daily_limit()
  returning count into g;
  if g is null then return -2; end if;
  insert into public.ai_usage (user_id, day, kind, count)
  values (p_user, (now() at time zone 'utc')::date, p_kind, 1)
  on conflict (user_id, day, kind) do update set count = public.ai_usage.count + 1
    where public.ai_usage.count < lim
  returning count into used;
  if used is null then
    update public.ai_usage_global set count = greatest(count - 1, 0) where day = (now() at time zone 'utc')::date;
    return -1;
  end if;
  return lim - used;
end $$;

create or replace function public.refund_ai_quota(p_user uuid, p_kind text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.ai_usage set count = greatest(count - 1, 0)
  where user_id = p_user and day = (now() at time zone 'utc')::date and kind = p_kind;
  update public.ai_usage_global set count = greatest(count - 1, 0) where day = (now() at time zone 'utc')::date;
end $$;

revoke all on function public.consume_ai_quota(uuid, text) from public, anon, authenticated;
revoke all on function public.refund_ai_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.consume_ai_quota(uuid, text) to service_role;
grant execute on function public.refund_ai_quota(uuid, text) to service_role;
