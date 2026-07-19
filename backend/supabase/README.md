# Supabase Setup

1. Create a Supabase project in the region closest to the primary player population.
2. Apply `migrations/202607190001_initial_online_schema.sql` with the Supabase CLI or SQL editor.
3. Configure Auth email/password and custom SMTP before production.
4. Copy only the project URL and publishable key into `config/backend_config.json`.
5. Never place a secret key, service-role key, database password, or access token in the Godot project.
6. Match results, ratings, bans, and moderation changes must be written by a trusted backend only.

The migration enables RLS on all exposed tables. Client users can read or update only their own profile/preferences and can create their own legal acceptance/report/deletion request records.
