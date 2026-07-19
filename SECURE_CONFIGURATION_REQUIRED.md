# Secure configuration required for deployment

The game client accepts only client-safe values:

- `SUPABASE_URL`
- Supabase **publishable** key (`sb_publishable_...`) or legacy `anon` key
- Public HTTPS URL of the deployed Rivet control plane

Never place these values in the Godot client or chat attachments:

- Supabase `sb_secret_...`
- Supabase `service_role`
- Database password or database connection string
- Rivet allocator/service token
- JWT signing private keys

For automated Supabase migration deployment, use a temporary Supabase Personal Access Token and project reference only in the deployment environment, then revoke the token. For Rivet deployment, authenticate the Rivet CLI in the deployment environment; do not copy its credentials into `config/backend_config.json`.

Configure the client before export:

```bash
python tools/configure_online.py \
  --supabase-url "https://PROJECT.supabase.co" \
  --supabase-publishable-key "sb_publishable_REDACTED" \
  --rivet-control-url "https://CONTROL.example.com" \
  --environment production
```
