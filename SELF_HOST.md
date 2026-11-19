# Self-hosting Saifuban

You don't have to trust the hosted service with your API keys. Everything that runs it is in this repo, and it fits on the free tiers of Supabase and Cloudflare.

What runs where:

| Part | Where | Code |
|---|---|---|
| Database (budgets, reservations, prices, encrypted provider keys) | Supabase Postgres | `supabase/migrations/` |
| API proxy, payment-approval API, dashboard API, MCP server, passkeys | Supabase Edge Functions | `supabase/functions/` |
| Streaming relay for long responses (optional) | Cloudflare Worker | `cloudflare/worker.js` |
| Setup command | your machine | `cli/saifuban.mjs` |

Provider keys are stored in Supabase Vault (encrypted at rest) and only read by the proxy. Agents only ever see their `sbk_...` key.

## 1. Database

Create a Supabase project, then run `supabase/migrations/20261119000000_saifuban.sql` once, either in the SQL editor or with the CLI:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

It enables `pg_net` and `pg_cron`, creates the tables and functions, seeds starting prices, creates two random secrets in Vault, and schedules an hourly job that refreshes model prices (from OpenRouter's public model list) and the USD/JPY rate once a day.

## 2. Edge functions

```bash
supabase functions deploy saifuban saifuban-app saifuban-proxy saifuban-mcp saifuban-passkey --no-verify-jwt
```

`--no-verify-jwt` is needed because the functions check Saifuban's own keys (`sbk_...` for agents, `sbo_...` for owners) instead of Supabase JWTs.

Optional environment variables (Edge Functions → Secrets):

- `SAIFUBAN_PUBLIC_BASE`: your Worker's address, if you deploy it (used by the MCP server's OAuth metadata)
- `SAIFUBAN_SITE_URL`: where you host the dashboard, if you host it (for the OAuth consent page and passkey sign-in)

At this point the proxy already works at `https://<ref>.supabase.co/functions/v1/saifuban-proxy/anthropic` (and `/openai/v1`, `/google`, `/openrouter/v1`). On Supabase's free plan a single request is cut after about 150 seconds, so long streaming responses need the Worker below.

## 3. Cloudflare Worker (for long responses)

```bash
npx wrangler deploy cloudflare/worker.js --name saifuban --compatibility-date 2026-11-17
npx wrangler secret put RELAY_SECRET --name saifuban
```

For `RELAY_SECRET`, paste the value from:

```sql
select decrypted_secret from vault.decrypted_secrets where name = 'saifuban_relay_secret';
```

Then set two plain variables on the Worker (Settings → Variables): `SUPABASE_URL` = `https://<ref>.supabase.co` and `PUBLIC_BASE` = the Worker's own address. The Worker only streams bytes. Budget checks, reservations and settlement still happen in Supabase.

## 4. Create your account and an agent

```bash
SAIFUBAN_API=https://<ref>.supabase.co/functions/v1/saifuban-app \
SAIFUBAN_RELAY=https://saifuban.<you>.workers.dev/proxy \
npx https://github.com/ut181749ut/saifuban/archive/refs/heads/main.tar.gz
```

Leave out `SAIFUBAN_RELAY` if you skipped the Worker. The command creates an owner passphrase (`sbo_...`), an agent with a daily budget, stores your provider key, and prints (or saves to `~/.claude/settings.json`) the base URL and agent key.

## 5. Dashboard (optional)

The dashboard is the static `index.html` in this repo. To point it at your project, change two lines near the top of its script:

```js
const PROJECT="<your-project-ref>";
const RELAY="https://saifuban.<you>.workers.dev/proxy";
```

and the `API` line in `authorize.html` (the OAuth consent page), then host the folder anywhere static (GitHub Pages works). You can also skip it: budgets live in the `agents` table (`daily`, `weekly`, `monthly`, `max_concurrent`), and spend is in `requests`.

## Checking it works

```bash
curl -sS "$ANTHROPIC_BASE_URL/v1/messages" \
  -H "x-api-key: $ANTHROPIC_AUTH_TOKEN" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5","max_tokens":16,"messages":[{"role":"user","content":"hi"}]}'
```

A normal reply means the agent key, the stored provider key and the budget check all work. The response carries `x-saifuban-remaining-jpy`.

The SQL tests in `tests/` run against your database too. Each one rolls itself back.
