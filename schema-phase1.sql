-- Phase 1 SQL migration for Pure Ice Food Safety System
-- Purpose: create profiles/users table linked to Supabase Auth, role management, and secure RLS

create extension if not exists pgcrypto;

-- 1) Roles
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

insert into public.roles (name, description)
values
  ('Super Admin', 'Full system access'),
  ('General Manager', 'Management oversight and approvals'),
  ('Quality & Food Safety', 'Quality and compliance oversight'),
  ('Production', 'Production and manufacturing records'),
  ('Maintenance', 'Equipment and maintenance oversight'),
  ('Warehouse', 'Inventory and warehouse control'),
  ('Purchasing', 'Supplier and procurement coordination'),
  ('Sales', 'Commercial and customer-facing operations'),
  ('Auditor / Read Only', 'Read-only audit access')
on conflict (name) do nothing;

-- 2) Departments
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text,
  location text,
  status text default 'active' check (status in ('active','inactive')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

insert into public.departments (name, code, location, status)
values
  ('Quality & Food Safety', 'QFS', 'Plant', 'active'),
  ('Production', 'PROD', 'Plant', 'active'),
  ('Maintenance', 'MNT', 'Plant', 'active'),
  ('Warehouse', 'WH', 'Plant', 'active'),
  ('Purchasing', 'PUR', 'Office', 'active'),
  ('Sales', 'SAL', 'Office', 'active'),
  ('Administration', 'ADM', 'Office', 'active')
on conflict (name) do nothing;

-- 3) Profiles linked to Supabase Auth users
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  employee_code text,
  department_id uuid references public.departments(id) on delete set null,
  role text not null default 'Auditor / Read Only',
  job_title text,
  phone text,
  status text default 'active' check (status in ('active','inactive')),
  avatar_url text,
  language text default 'en' check (language in ('en','ar')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 4) Updated-at trigger
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_roles_updated_at on public.roles;
create trigger set_roles_updated_at
before update on public.roles
for each row execute function public.set_updated_at();

drop trigger if exists set_departments_updated_at on public.departments;
create trigger set_departments_updated_at
before update on public.departments
for each row execute function public.set_updated_at();

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- 5) Access helpers
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
as $$
  select coalesce(
    (
      select true
      from public.profiles
      where id = auth.uid()
        and role = 'Super Admin'
    ),
    false
  );
$$;

create or replace function public.is_manager()
returns boolean
language sql
stable
security definer
as $$
  select coalesce(
    (
      select true
      from public.profiles
      where id = auth.uid()
        and role in ('Super Admin', 'General Manager')
    ),
    false
  );
$$;

-- 6) RLS on core tables
alter table public.roles enable row level security;
alter table public.departments enable row level security;
alter table public.profiles enable row level security;

-- 7) Roles policies
drop policy if exists "roles_authenticated_select" on public.roles;
create policy "roles_authenticated_select"
on public.roles
for select
using (auth.role() = 'authenticated');

drop policy if exists "roles_admin_all" on public.roles;
create policy "roles_admin_all"
on public.roles
for all
using (public.is_admin())
with check (public.is_admin());

-- 8) Departments policies

drop policy if exists "departments_authenticated_select" on public.departments;
create policy "departments_authenticated_select"
on public.departments
for select
using (auth.role() = 'authenticated');

drop policy if exists "departments_admin_all" on public.departments;
create policy "departments_admin_all"
on public.departments
for all
using (public.is_admin())
with check (public.is_admin());

-- 9) Profiles policies

drop policy if exists "profiles_select_self_or_admin" on public.profiles;
create policy "profiles_select_self_or_admin"
on public.profiles
for select
using (auth.uid() = id or public.is_admin());

drop policy if exists "profiles_update_self_or_admin" on public.profiles;
create policy "profiles_update_self_or_admin"
on public.profiles
for update
using (auth.uid() = id or public.is_admin())
with check (auth.uid() = id or public.is_admin());

drop policy if exists "profiles_admin_all" on public.profiles;
create policy "profiles_admin_all"
on public.profiles
for all
using (public.is_admin())
with check (public.is_admin());

-- 10) Helpful indexes
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_profiles_department on public.profiles(department_id);
create index if not exists idx_profiles_status on public.profiles(status);
create index if not exists idx_departments_status on public.departments(status);

-- 11) Assign the existing auth user as Super Admin
-- Replace the UUID below with the actual auth user id from Supabase Authentication > Users
-- Example:
-- select id, email from auth.users where email = 'your-user@example.com';
-- then update/insert the profile for that auth user and set role = 'Super Admin'

-- Example insert-or-update block:
-- insert into public.profiles (
--   id,
--   full_name,
--   email,
--   employee_code,
--   department_id,
--   role,
--   job_title,
--   phone,
--   status,
--   language
-- )
-- values (
--   'PASTE_AUTH_USER_UUID_HERE',
--   'Pure Ice Admin',
--   'your-user@example.com',
--   'PI-ADMIN',
--   (select id from public.departments where name = 'Administration' limit 1),
--   'Super Admin',
--   'System Administrator',
--   '+966000000000',
--   'active',
--   'en'
-- )
-- on conflict (id) do update
-- set
--   full_name = excluded.full_name,
--   email = excluded.email,
--   employee_code = excluded.employee_code,
--   department_id = excluded.department_id,
--   role = 'Super Admin',
--   job_title = excluded.job_title,
--   phone = excluded.phone,
--   status = 'active',
--   language = excluded.language,
--   updated_at = now();

-- Or if the profile already exists:
-- update public.profiles
-- set role = 'Super Admin',
--     job_title = 'System Administrator',
--     status = 'active',
--     updated_at = now()
-- where id = 'PASTE_AUTH_USER_UUID_HERE';
