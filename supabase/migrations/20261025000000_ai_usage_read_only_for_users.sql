-- Users may read their own usage (RLS policy) but never write it; only the edge functions (service_role) change counts.
revoke insert, update, delete, truncate, references, trigger on public.ai_usage from anon, authenticated;
revoke select on public.ai_usage from anon;
