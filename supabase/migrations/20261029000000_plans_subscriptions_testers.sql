-- UMEVA v1 ships with UMEVA+.
-- Limits per day: free Coach 3 / photo+menu 1 / Chef 1; UMEVA+ 15 / 10 / 5; testers 50 / 30 / 30.
-- A subscription counts only after the `entitlement` (or `appstore-notifications`) edge function
-- verified Apple's signed transaction. The app can't grant itself a plan.

create table if not exists public.subscriptions (
  original_transaction_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  environment text not null check (environment in ('Production','Sandbox','Xcode','LocalTesting')),
  expires_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now()
);
create index if not exists subscriptions_user_idx on public.subscriptions (user_id);
alter table public.subscriptions enable row level security;
revoke all on public.subscriptions from anon, authenticated;
grant select on public.subscriptions to authenticated;
drop policy if exists "read own subscriptions" on public.subscriptions;
create policy "read own subscriptions" on public.subscriptions
  for select to authenticated using ((select auth.uid()) = user_id);

create table if not exists public.ai_testers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  note text,
  added_at timestamptz not null default now()
);
alter table public.ai_testers enable row level security;
revoke all on public.ai_testers from anon, authenticated;

-- Base (free) limit; also the list of valid kinds.
create or replace function public.ai_daily_limit(p_kind text)
returns integer language sql immutable set search_path = '' as $$
  select case p_kind when 'coach' then 3 when 'photo' then 1 when 'chef' then 1 else 0 end;
$$;

create or replace function public.ai_user_plan(p_user uuid)
returns text language sql stable set search_path = '' as $$
  select case
    when exists (select 1 from public.ai_testers t where t.user_id = p_user) then 'tester'
    when exists (
      select 1 from public.subscriptions s
      where s.user_id = p_user and s.revoked_at is null and s.expires_at > now()
        and s.environment in ('Production','Sandbox')
    ) then 'plus'
    else 'free'
  end;
$$;

create or replace function public.ai_user_daily_limit(p_user uuid, p_kind text)
returns integer language sql stable set search_path = '' as $$
  select case
    when public.ai_daily_limit(p_kind) = 0 then 0
    else case public.ai_user_plan(p_user)
      when 'tester' then case p_kind when 'coach' then 50 when 'photo' then 30 when 'chef' then 30 end
      when 'plus'   then case p_kind when 'coach' then 15 when 'photo' then 10 when 'chef' then 5 end
      else public.ai_daily_limit(p_kind)
    end
  end;
$$;

create or replace function public.consume_ai_quota(p_user uuid, p_kind text)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  lim integer := public.ai_user_daily_limit(p_user, p_kind);
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

revoke all on function public.ai_user_plan(uuid) from public, anon, authenticated;
revoke all on function public.ai_user_daily_limit(uuid, text) from public, anon, authenticated;
revoke all on function public.consume_ai_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.ai_user_plan(uuid) to service_role;
grant execute on function public.ai_user_daily_limit(uuid, text) to service_role;
grant execute on function public.consume_ai_quota(uuid, text) to service_role;

-- Owner account as tester (higher limits, may use Xcode StoreKit test purchases).
insert into public.ai_testers (user_id, note)
values ('166ae91f-eb39-4fc0-a653-7797f2b44377', 'Mark (owner)')
on conflict do nothing;
