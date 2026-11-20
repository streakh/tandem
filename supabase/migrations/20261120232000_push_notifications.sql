-- Push notifications: which phones to notify, and each person's preferences.

create table public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users on delete cascade,
  environment text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);
create index on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
create policy device_tokens_select on public.device_tokens for select to authenticated using (user_id = (select auth.uid()));
create policy device_tokens_delete on public.device_tokens for delete to authenticated using (user_id = (select auth.uid()));

-- A phone belongs to whoever is signed in on it right now, so registering moves the token to the caller.
create or replace function public.register_device_token(p_token text, p_environment text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into public.device_tokens (token, user_id, environment)
  values (p_token, auth.uid(), case when p_environment = 'production' then 'production' else 'sandbox' end)
  on conflict (token) do update set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();
end $$;

revoke execute on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;

alter table public.profiles
  add column notify_tasks boolean not null default true,
  add column notify_notes boolean not null default true;
