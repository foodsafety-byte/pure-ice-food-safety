-- Phase 2 SQL migration for Pure Ice Food Safety System
-- Purpose: User & Role Management - RLS policies and helper functions
-- Note: Core tables (profiles, roles, departments) are created in Phase 1
-- This script ensures all necessary policies are in place for user management operations

-- 1) Ensure RLS is enabled on all tables (should already be enabled from Phase 1)
alter table public.roles enable row level security;
alter table public.departments enable row level security;
alter table public.profiles enable row level security;

-- 2) Verify is_admin() function exists (created in Phase 1)
-- The is_admin() function checks if the current user has role = 'Super Admin'

-- 3) Additional helper function for checking if user can manage users
create or replace function public.can_manage_users()
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

-- 4) Ensure all RLS policies support user management operations
-- The following policies are already created in Phase 1:

-- Profiles: Super Admin can view all, edit all, insert new users
-- RLS policy allows is_admin() for all operations on profiles

-- Roles: Super Admin can view and manage all roles
-- RLS policy allows is_admin() for all operations on roles

-- Departments: Super Admin can view and manage all departments
-- RLS policy allows is_admin() for all operations on departments

-- 5) Create audit log table for user management changes (optional but recommended)
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  table_name text,
  record_id uuid,
  old_values jsonb,
  new_values jsonb,
  timestamp timestamptz default now()
);

-- Enable RLS on audit logs
alter table public.audit_logs enable row level security;

-- Only authenticated users can insert audit logs (system operations)
drop policy if exists "audit_logs_insert" on public.audit_logs;
create policy "audit_logs_insert"
on public.audit_logs
for insert
with check (auth.role() = 'authenticated');

-- Only Super Admin can view audit logs
drop policy if exists "audit_logs_admin_select" on public.audit_logs;
create policy "audit_logs_admin_select"
on public.audit_logs
for select
using (public.is_admin());

-- Create index for audit log queries
create index if not exists idx_audit_logs_actor on public.audit_logs(actor_id);
create index if not exists idx_audit_logs_table on public.audit_logs(table_name);
create index if not exists idx_audit_logs_timestamp on public.audit_logs(timestamp);

-- Phase 2 Schema is complete. The profiles, roles, and departments tables 
-- from Phase 1 are sufficient for User & Role Management functionality.
-- All RLS policies are in place to enforce Super Admin access control.
