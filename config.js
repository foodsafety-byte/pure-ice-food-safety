// Supabase Configuration - PUBLIC ONLY
// !! NEVER put secret keys or service role keys here !!

const SUPABASE_CONFIG = {
  // Get these from: https://app.supabase.com/project/[project-id]/settings/api
  URL: import.meta.env.VITE_SUPABASE_URL || "https://your-project.supabase.co",
  ANON_KEY: import.meta.env.VITE_SUPABASE_ANON_KEY || "your-anon-key-here"
};

// Export for use in other modules
export default SUPABASE_CONFIG;
