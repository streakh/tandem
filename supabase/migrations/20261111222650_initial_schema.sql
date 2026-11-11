-- Tandem: shared pet-care record. Schema, access rules, RPCs.

create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.gen_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  result text := '';
begin
  for i in 1..6 loop
    result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return result;
end $$;

-- ---------- tables ----------

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique default private.gen_code(),
  created_by uuid references auth.users on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  display_name text not null default '',
  created_at timestamptz not null default now(),
  primary key (household_id, user_id)
);
create index on public.household_members (user_id);

create table public.pets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households on delete cascade,
  name text not null,
  species text not null default 'other',
  breed text not null default '',
  sex text not null default '',
  birthdate date,
  weight numeric,
  weight_unit text not null default 'lb',
  photo_path text,
  notes text not null default '',
  microchip text not null default '',
  vet_name text not null default '',
  vet_clinic text not null default '',
  vet_phone text not null default '',
  vet_address text not null default '',
  emergency_name text not null default '',
  emergency_phone text not null default '',
  created_at timestamptz not null default now()
);
create index on public.pets (household_id);

create table public.medications (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets on delete cascade,
  name text not null,
  dose text not null default '',
  frequency text not null default '',
  instructions text not null default '',
  start_date date,
  end_date date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.medications (pet_id);

create table public.routines (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets on delete cascade,
  category text not null check (category in ('feeding','water','walk','medication','cleaning','grooming','play','vet','other')),
  title text not null,
  details text not null default '',
  amount text not null default '',
  time_of_day time,
  schedule text not null default 'daily' check (schedule in ('daily','weekly','interval','once')),
  weekdays smallint[] not null default '{}',
  interval_days int,
  start_date date not null default current_date,
  end_date date,
  medication_id uuid references public.medications on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.routines (pet_id);

create table public.care_plans (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households on delete cascade,
  title text not null default '',
  caregiver_label text not null default '',
  start_date date not null,
  end_date date not null,
  categories text[] not null default '{}',
  notes text not null default '',
  emergency_notes text not null default '',
  invite_code text not null unique default private.gen_code(),
  status text not null default 'active' check (status in ('active','revoked')),
  sitter_id uuid references auth.users on delete set null,
  sitter_name text not null default '',
  created_by uuid references auth.users on delete set null default auth.uid(),
  created_by_name text not null default '',
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);
create index on public.care_plans (household_id);
create index on public.care_plans (sitter_id);

create table public.care_plan_pets (
  care_plan_id uuid not null references public.care_plans on delete cascade,
  pet_id uuid not null references public.pets on delete cascade,
  primary key (care_plan_id, pet_id)
);
create index on public.care_plan_pets (pet_id);

create table public.care_logs (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets on delete cascade,
  routine_id uuid references public.routines on delete set null,
  category text not null default 'other',
  title text not null,
  scheduled_for date not null,
  status text not null default 'done' check (status in ('done','skipped')),
  note text not null default '',
  logged_by uuid references auth.users on delete set null default auth.uid(),
  logged_by_name text not null default '',
  logged_at timestamptz not null default now(),
  care_plan_id uuid references public.care_plans on delete set null,
  -- the "already done" guarantee: one entry per routine per day
  unique (routine_id, scheduled_for)
);
create index on public.care_logs (pet_id, scheduled_for desc);

create table public.allergies (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets on delete cascade,
  name text not null,
  severity text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now()
);
create index on public.allergies (pet_id);

create table public.vaccines (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets on delete cascade,
  name text not null,
  date_given date,
  due_date date,
  notes text not null default '',
  created_at timestamptz not null default now()
);
create index on public.vaccines (pet_id);

create table public.weight_entries (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets on delete cascade,
  weight numeric not null,
  unit text not null default 'lb',
  measured_on date not null default current_date,
  created_at timestamptz not null default now()
);
create index on public.weight_entries (pet_id);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets on delete cascade,
  title text not null,
  kind text not null default '',
  storage_path text not null,
  created_at timestamptz not null default now()
);
create index on public.documents (pet_id);

create table public.events (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users on delete set null default auth.uid(),
  name text not null,
  props jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- ---------- access helpers (not exposed through the API) ----------

create or replace function private.is_member(hid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.household_members m
                 where m.household_id = hid and m.user_id = (select auth.uid()));
$$;

create or replace function private.is_owner(hid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.household_members m
                 where m.household_id = hid and m.user_id = (select auth.uid()) and m.role = 'owner');
$$;

create or replace function private.is_pet_member(pid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pets p
                 join public.household_members m on m.household_id = p.household_id
                 where p.id = pid and m.user_id = (select auth.uid()));
$$;

-- A sitter can see a pet from the moment they accept a plan until it ends
-- (one day of grace for time zones). cat/d narrow it to a category / a day.
create or replace function private.sitter_can(pid uuid, cat text, d date) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.care_plans cp
    join public.care_plan_pets cpp on cpp.care_plan_id = cp.id
    where cpp.pet_id = pid
      and cp.sitter_id = (select auth.uid())
      and cp.status = 'active'
      and current_date <= cp.end_date + 1
      and (cat is null or cat = 'note' or cat = any (cp.categories))
      and (d is null or d between cp.start_date and cp.end_date)
  );
$$;

create or replace function private.is_sitter_of_household(hid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.care_plans cp
                 where cp.household_id = hid and cp.sitter_id = (select auth.uid())
                   and cp.status = 'active' and current_date <= cp.end_date + 1);
$$;

create or replace function private.can_see_plan(plan uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.care_plans cp
                 where cp.id = plan
                   and (cp.sitter_id = (select auth.uid()) or private.is_member(cp.household_id)));
$$;

create or replace function private.can_edit_plan(plan uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.care_plans cp
                 where cp.id = plan and private.is_member(cp.household_id));
$$;

-- ---------- row level security ----------

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.pets enable row level security;
alter table public.medications enable row level security;
alter table public.routines enable row level security;
alter table public.care_plans enable row level security;
alter table public.care_plan_pets enable row level security;
alter table public.care_logs enable row level security;
alter table public.allergies enable row level security;
alter table public.vaccines enable row level security;
alter table public.weight_entries enable row level security;
alter table public.documents enable row level security;
alter table public.events enable row level security;

create policy profiles_select on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy households_select on public.households for select to authenticated
  using (private.is_member(id) or private.is_sitter_of_household(id));
create policy households_update on public.households for update to authenticated
  using (private.is_owner(id)) with check (private.is_owner(id));
create policy households_delete on public.households for delete to authenticated using (private.is_owner(id));

create policy members_select on public.household_members for select to authenticated using (private.is_member(household_id));
create policy members_delete on public.household_members for delete to authenticated
  using (user_id = (select auth.uid()) or private.is_owner(household_id));

create policy pets_select on public.pets for select to authenticated
  using (private.is_member(household_id) or private.sitter_can(id, null, null));
create policy pets_insert on public.pets for insert to authenticated with check (private.is_member(household_id));
create policy pets_update on public.pets for update to authenticated using (private.is_member(household_id)) with check (private.is_member(household_id));
create policy pets_delete on public.pets for delete to authenticated using (private.is_member(household_id));

create policy routines_select on public.routines for select to authenticated
  using (private.is_pet_member(pet_id) or private.sitter_can(pet_id, category, null));
create policy routines_insert on public.routines for insert to authenticated with check (private.is_pet_member(pet_id));
create policy routines_update on public.routines for update to authenticated using (private.is_pet_member(pet_id)) with check (private.is_pet_member(pet_id));
create policy routines_delete on public.routines for delete to authenticated using (private.is_pet_member(pet_id));

create policy logs_select on public.care_logs for select to authenticated
  using (private.is_pet_member(pet_id) or private.sitter_can(pet_id, category, scheduled_for));
create policy logs_insert on public.care_logs for insert to authenticated
  with check (logged_by = (select auth.uid())
              and (private.is_pet_member(pet_id) or private.sitter_can(pet_id, category, scheduled_for)));
create policy logs_update on public.care_logs for update to authenticated
  using (logged_by = (select auth.uid()) or private.is_pet_member(pet_id))
  with check (logged_by = (select auth.uid()) or private.is_pet_member(pet_id));
create policy logs_delete on public.care_logs for delete to authenticated
  using (logged_by = (select auth.uid()) or private.is_pet_member(pet_id));

create policy allergies_select on public.allergies for select to authenticated
  using (private.is_pet_member(pet_id) or private.sitter_can(pet_id, null, null));
create policy allergies_insert on public.allergies for insert to authenticated with check (private.is_pet_member(pet_id));
create policy allergies_update on public.allergies for update to authenticated using (private.is_pet_member(pet_id)) with check (private.is_pet_member(pet_id));
create policy allergies_delete on public.allergies for delete to authenticated using (private.is_pet_member(pet_id));

create policy medications_select on public.medications for select to authenticated
  using (private.is_pet_member(pet_id) or private.sitter_can(pet_id, 'medication', null));
create policy medications_insert on public.medications for insert to authenticated with check (private.is_pet_member(pet_id));
create policy medications_update on public.medications for update to authenticated using (private.is_pet_member(pet_id)) with check (private.is_pet_member(pet_id));
create policy medications_delete on public.medications for delete to authenticated using (private.is_pet_member(pet_id));

create policy vaccines_all on public.vaccines for all to authenticated using (private.is_pet_member(pet_id)) with check (private.is_pet_member(pet_id));
create policy weights_all on public.weight_entries for all to authenticated using (private.is_pet_member(pet_id)) with check (private.is_pet_member(pet_id));
create policy documents_all on public.documents for all to authenticated using (private.is_pet_member(pet_id)) with check (private.is_pet_member(pet_id));

create policy plans_select on public.care_plans for select to authenticated
  using (sitter_id = (select auth.uid()) or private.is_member(household_id));
create policy plans_insert on public.care_plans for insert to authenticated with check (private.is_member(household_id));
create policy plans_update on public.care_plans for update to authenticated using (private.is_member(household_id)) with check (private.is_member(household_id));
create policy plans_delete on public.care_plans for delete to authenticated using (private.is_member(household_id));

create policy plan_pets_select on public.care_plan_pets for select to authenticated using (private.can_see_plan(care_plan_id));
create policy plan_pets_insert on public.care_plan_pets for insert to authenticated with check (private.can_edit_plan(care_plan_id));
create policy plan_pets_delete on public.care_plan_pets for delete to authenticated using (private.can_edit_plan(care_plan_id));

create policy events_insert on public.events for insert to authenticated with check (user_id = (select auth.uid()));

-- ---------- triggers ----------

create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- keep the names shown to other caregivers in step with the profile
create or replace function private.sync_display_name() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.display_name is distinct from old.display_name then
    update public.household_members set display_name = new.display_name where user_id = new.id;
    update public.care_plans set sitter_name = new.display_name where sitter_id = new.id;
    update public.care_plans set created_by_name = new.display_name where created_by = new.id;
  end if;
  return new;
end $$;

create trigger on_profile_updated after update on public.profiles
  for each row execute function private.sync_display_name();

-- ---------- RPCs ----------

create or replace function public.create_household(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  hid uuid;
begin
  if uid is null then raise exception 'Not signed in'; end if;
  insert into public.households (name, created_by) values (trim(p_name), uid) returning id into hid;
  insert into public.household_members (household_id, user_id, role, display_name)
  values (hid, uid, 'owner', coalesce((select display_name from public.profiles where id = uid), ''));
  return hid;
end $$;

create or replace function public.redeem_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  my_name text;
  hid uuid;
  plan public.care_plans%rowtype;
begin
  if uid is null then raise exception 'Not signed in'; end if;
  select display_name into my_name from public.profiles where id = uid;

  select id into hid from public.households where invite_code = code;
  if found then
    insert into public.household_members (household_id, user_id, role, display_name)
    values (hid, uid, 'member', coalesce(my_name, ''))
    on conflict do nothing;
    return jsonb_build_object('kind', 'household', 'id', hid);
  end if;

  select * into plan from public.care_plans where invite_code = code;
  if found then
    if plan.status <> 'active' then raise exception 'This care plan is no longer active.'; end if;
    if current_date > plan.end_date + 1 then raise exception 'This care plan has already ended.'; end if;
    if plan.sitter_id is not null and plan.sitter_id <> uid then
      raise exception 'This invite has already been used by someone else.';
    end if;
    if private.is_member(plan.household_id) then
      raise exception 'You are already part of this household.';
    end if;
    update public.care_plans
       set sitter_id = uid, sitter_name = coalesce(my_name, ''), accepted_at = coalesce(accepted_at, now())
     where id = plan.id;
    return jsonb_build_object('kind', 'care_plan', 'id', plan.id);
  end if;

  raise exception 'We could not find that invite code.';
end $$;

create or replace function public.rotate_household_code(p_household uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare new_code text;
begin
  if not private.is_owner(p_household) then raise exception 'Only an owner can do this.'; end if;
  new_code := private.gen_code();
  update public.households set invite_code = new_code where id = p_household;
  return new_code;
end $$;

revoke execute on function public.create_household(text) from public, anon;
revoke execute on function public.redeem_invite(text) from public, anon;
revoke execute on function public.rotate_household_code(uuid) from public, anon;
grant execute on function public.create_household(text) to authenticated;
grant execute on function public.redeem_invite(text) to authenticated;
grant execute on function public.rotate_household_code(uuid) to authenticated;

-- ---------- realtime ----------

alter publication supabase_realtime add table
  public.households, public.household_members, public.pets, public.routines, public.care_logs,
  public.care_plans, public.care_plan_pets, public.allergies, public.medications, public.vaccines,
  public.weight_entries, public.documents;

-- ---------- storage (pet photos and documents) ----------
-- paths: <household_id>/<pet_id>/photo-*.jpg  and  <household_id>/<pet_id>/docs/*

insert into storage.buckets (id, name, public) values ('pet-files', 'pet-files', false)
on conflict (id) do nothing;

create policy pet_files_member_select on storage.objects for select to authenticated
  using (bucket_id = 'pet-files' and private.is_member(((storage.foldername(name))[1])::uuid));
create policy pet_files_member_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'pet-files' and private.is_member(((storage.foldername(name))[1])::uuid));
create policy pet_files_member_update on storage.objects for update to authenticated
  using (bucket_id = 'pet-files' and private.is_member(((storage.foldername(name))[1])::uuid));
create policy pet_files_member_delete on storage.objects for delete to authenticated
  using (bucket_id = 'pet-files' and private.is_member(((storage.foldername(name))[1])::uuid));
create policy pet_files_sitter_photo on storage.objects for select to authenticated
  using (bucket_id = 'pet-files'
         and array_length(storage.foldername(name), 1) = 2
         and private.sitter_can(((storage.foldername(name))[2])::uuid, null, null));
