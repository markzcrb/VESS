-- AI Chef gets its own daily quota (10 per day in the free beta).
alter table public.ai_usage drop constraint if exists ai_usage_kind_check;
alter table public.ai_usage add constraint ai_usage_kind_check check (kind in ('coach','photo','chef'));

create or replace function public.ai_daily_limit(p_kind text)
returns integer language sql immutable set search_path = '' as $$
  select case p_kind when 'coach' then 20 when 'photo' then 10 when 'chef' then 10 else 0 end;
$$;
