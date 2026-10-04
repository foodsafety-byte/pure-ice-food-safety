-- ============================================
-- PURE ICE FOOD SAFETY SYSTEM
-- Phase 1: User Profiles & Role Management
-- ============================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================
-- 1. Roles table
-- ============================================
CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Seed roles
INSERT INTO public.roles (name, description) VALUES
  ('Super Admin', 'Full system administration rights'),
  ('General Manager', 'Management oversight and approvals'),
  ('Quality & Food Safety', 'Quality and compliance oversight'),
  ('Production', 'Production and manufacturing records'),
  ('Maintenance', 'Equipment and maintenance oversight'),
  ('Warehouse', 'Inventory and warehouse control'),
  ('Purchasing', 'Supplier and procurement coordination'),
  ('Sales', 'Commercial and customer-facing operations'),
  ('Auditor / Read Only', 'Read-only audit access')
ON CONFLICT (name) DO NOTHING;

-- ============================================
-- 2. Departments table
-- ============================================
CREATE TABLE IF NOT EXISTS public.departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  code TEXT,
  location TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Seed departments
INSERT INTO public.departments (name, code, location, status) VALUES
  ('Quality & Food Safety', 'QFS', 'Plant', 'active'),
  ('Production', 'PROD', 'Plant', 'active'),
  ('Maintenance', 'MNT', 'Plant', 'active'),
  ('Warehouse', 'WH', 'Plant', 'active'),
  ('Purchasing', 'PUR', 'Office', 'active'),
  ('Sales', 'SAL', 'Office', 'active'),
  ('Administration', 'ADM', 'Office', 'active')
ON CONFLICT (name) DO NOTHING;

-- ============================================
-- 3. Profiles table (linked to auth.users)
-- ============================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  email TEXT,
  employee_code TEXT,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  role TEXT NOT NULL DEFAULT 'Auditor / Read Only' REFERENCES public.roles(name),
  job_title TEXT,
  phone TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  avatar_url TEXT,
  language TEXT DEFAULT 'en' CHECK (language IN ('en', 'ar')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 4. Triggers for updated_at
-- ============================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_roles_updated_at ON public.roles;
CREATE TRIGGER set_roles_updated_at BEFORE UPDATE ON public.roles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_departments_updated_at ON public.departments;
CREATE TRIGGER set_departments_updated_at BEFORE UPDATE ON public.departments
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================
-- 5. Helper functions for role/access checks
-- ============================================
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE((SELECT TRUE FROM public.profiles WHERE id = auth.uid() AND role = 'Super Admin'), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.is_manager()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE((SELECT TRUE FROM public.profiles WHERE id = auth.uid() AND role IN ('Super Admin', 'General Manager')), FALSE);
$$;

-- ============================================
-- 6. Enable Row Level Security (RLS)
-- ============================================
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 7. RLS Policies for Roles table
-- ============================================
DROP POLICY IF EXISTS "Authenticated users can view roles" ON public.roles;
CREATE POLICY "Authenticated users can view roles"
  ON public.roles FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Only admins can manage roles" ON public.roles;
CREATE POLICY "Only admins can manage roles"
  ON public.roles FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================
-- 8. RLS Policies for Departments table
-- ============================================
DROP POLICY IF EXISTS "Authenticated users can view departments" ON public.departments;
CREATE POLICY "Authenticated users can view departments"
  ON public.departments FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Only admins can manage departments" ON public.departments;
CREATE POLICY "Only admins can manage departments"
  ON public.departments FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================
-- 9. RLS Policies for Profiles table
-- ============================================
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id OR public.is_admin())
  WITH CHECK (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "Admins can manage all profiles" ON public.profiles;
CREATE POLICY "Admins can manage all profiles"
  ON public.profiles FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================
-- 10. Indexes for performance
-- ============================================
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_status ON public.profiles(status);
CREATE INDEX IF NOT EXISTS idx_profiles_department ON public.profiles(department_id);
CREATE INDEX IF NOT EXISTS idx_departments_status ON public.departments(status);

-- ============================================
-- Note: After running this SQL:
-- 1. Set the authenticated user's role to 'Super Admin' in the profiles table
-- 2. Example UPDATE:
--    UPDATE public.profiles 
--    SET role = 'Super Admin' 
--    WHERE id = 'USER_UUID_HERE';
-- ============================================
