-- Saifuban: full database schema (generated from the running service, 2026-11-19)
-- Run this once on a fresh Supabase project (SQL editor, or `supabase db push`).
-- See SELF_HOST.md for the remaining steps.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net;
create extension if not exists pg_cron;
-- supabase_vault is enabled by default on Supabase

set check_function_bodies = off;

-- tables
create table if not exists public.agents (
  id uuid default gen_random_uuid() not null,
  name text not null,
  key_hash text not null,
  key_hint text not null,
  per_tx integer default 5000 not null,
  daily integer default 20000 not null,
  auto_approve integer default 0 not null,
  merchants text[] default '{}'::text[] not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  owner_id uuid,
  archived boolean default false not null,
  weekly integer,
  monthly integer,
  auto_known_only boolean default false not null,
  max_concurrent integer default 8 not null
);

create table if not exists public.oauth_clients (
  client_id text not null,
  client_name text,
  redirect_uris text[] not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.oauth_requests (
  id text not null,
  client_id text not null,
  redirect_uri text not null,
  code_challenge text not null,
  state text,
  scope text,
  created_at timestamp with time zone default now() not null,
  agent_id uuid,
  code_hash text,
  code_expires timestamp with time zone,
  used boolean default false not null
);

create table if not exists public.oauth_tokens (
  id bigserial,
  agent_id uuid not null,
  client_id text not null,
  access_hash text not null,
  refresh_hash text,
  access_expires timestamp with time zone not null,
  refresh_expires timestamp with time zone not null,
  revoked boolean default false not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.owner_device_keys (
  key_hash text not null,
  owner_id uuid not null,
  key_hint text,
  via text default 'passkey'::text not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.owner_passkeys (
  id uuid default gen_random_uuid() not null,
  owner_id uuid not null,
  credential_id text not null,
  public_key text not null,
  counter bigint default 0 not null,
  transports text[],
  rp_id text not null,
  created_at timestamp with time zone default now() not null,
  last_used_at timestamp with time zone
);

create table if not exists public.owner_provider_keys (
  owner_id uuid not null,
  provider text not null,
  secret_id uuid not null,
  hint text default ''::text not null,
  enabled boolean default true not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.owners (
  id uuid default gen_random_uuid() not null,
  key_hash text not null,
  key_hint text not null,
  kill boolean default false not null,
  ntfy_topic text,
  created_at timestamp with time zone default now() not null,
  lang text default 'ja'::text not null,
  currency text default 'JPY'::text not null,
  tz text default 'Asia/Tokyo'::text not null,
  tz_set boolean default false not null
);

create table if not exists public.passkey_challenges (
  id uuid default gen_random_uuid() not null,
  challenge text not null,
  owner_id uuid,
  kind text not null,
  rp_id text not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.prices (
  provider text not null,
  model_prefix text not null,
  input_per_mtok numeric not null,
  output_per_mtok numeric not null,
  source text default 'manual'::text not null,
  updated_at timestamp with time zone default now() not null,
  long_threshold bigint,
  long_input_per_mtok numeric,
  long_output_per_mtok numeric,
  max_output integer
);

create table if not exists public.provider_keys (
  provider text not null,
  secret_id uuid not null,
  hint text not null,
  enabled boolean default true not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.proxy_inflight (
  id bigserial,
  agent_id uuid not null,
  started_at timestamp with time zone default now() not null,
  reserved_jpy numeric default 0 not null,
  provider text,
  model text,
  settled_at timestamp with time zone,
  settled_jpy numeric,
  request_id bigint,
  basis text,
  est_usd numeric,
  is_generation boolean
);

create table if not exists public.push_subs (
  endpoint text not null,
  owner_id uuid not null,
  p256dh text not null,
  auth text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.requests (
  id bigint generated always as identity not null,
  agent_id uuid not null,
  merchant text not null,
  amount numeric(14,2) not null,
  reason text default ''::text not null,
  status text not null,
  note text default ''::text not null,
  day date not null,
  created_at timestamp with time zone default now() not null,
  decided_at timestamp with time zone,
  token_hash text,
  source text default 'request'::text not null,
  redeemed_at timestamp with time zone,
  redeemed_by text,
  recurring text,
  recurring_detected boolean default false not null,
  first_merchant boolean default false not null,
  idem_key text
);

create table if not exists public.settings (
  id integer default 1 not null,
  kill boolean default false not null,
  updated_at timestamp with time zone default now() not null,
  ntfy_topic text,
  usd_jpy numeric(8,2) default 155 not null,
  app_url text default 'https://claude.ai/artifact/L54EiKWFzC5GjPQEXn9n7A'::text not null,
  vapid_secret_id uuid,
  vapid_public text,
  usd_jpy_updated_at timestamp with time zone
);

create table if not exists public.site_stats (
  day date default ((now() AT TIME ZONE 'Asia/Tokyo'::text))::date not null,
  event text not null,
  src text default 'direct'::text not null,
  lang text default 'ja'::text not null,
  n integer default 0 not null
);

create table if not exists public.sync_jobs (
  kind text not null,
  req_id bigint,
  requested_at timestamp with time zone,
  last_ok_at timestamp with time zone,
  last_note text
);

-- constraints
alter table public.agents add constraint agents_pkey PRIMARY KEY (id);
alter table public.oauth_clients add constraint oauth_clients_pkey PRIMARY KEY (client_id);
alter table public.oauth_requests add constraint oauth_requests_pkey PRIMARY KEY (id);
alter table public.oauth_tokens add constraint oauth_tokens_pkey PRIMARY KEY (id);
alter table public.owner_device_keys add constraint owner_device_keys_pkey PRIMARY KEY (key_hash);
alter table public.owner_passkeys add constraint owner_passkeys_pkey PRIMARY KEY (id);
alter table public.owner_provider_keys add constraint owner_provider_keys_pkey PRIMARY KEY (owner_id, provider);
alter table public.owners add constraint owners_pkey PRIMARY KEY (id);
alter table public.passkey_challenges add constraint passkey_challenges_pkey PRIMARY KEY (id);
alter table public.prices add constraint prices_pkey PRIMARY KEY (provider, model_prefix);
alter table public.provider_keys add constraint provider_keys_pkey PRIMARY KEY (provider);
alter table public.proxy_inflight add constraint proxy_inflight_pkey PRIMARY KEY (id);
alter table public.push_subs add constraint push_subs_pkey PRIMARY KEY (endpoint);
alter table public.requests add constraint requests_pkey PRIMARY KEY (id);
alter table public.settings add constraint settings_pkey PRIMARY KEY (id);
alter table public.site_stats add constraint site_stats_pkey PRIMARY KEY (day, event, src, lang);
alter table public.sync_jobs add constraint sync_jobs_pkey PRIMARY KEY (kind);
alter table public.agents add constraint agents_key_hash_key UNIQUE (key_hash);
alter table public.oauth_requests add constraint oauth_requests_code_hash_key UNIQUE (code_hash);
alter table public.oauth_tokens add constraint oauth_tokens_access_hash_key UNIQUE (access_hash);
alter table public.oauth_tokens add constraint oauth_tokens_refresh_hash_key UNIQUE (refresh_hash);
alter table public.owner_passkeys add constraint owner_passkeys_credential_id_key UNIQUE (credential_id);
alter table public.owners add constraint owners_key_hash_key UNIQUE (key_hash);
alter table public.agents add constraint agents_auto_approve_check CHECK ((auto_approve >= 0));
alter table public.agents add constraint agents_daily_check CHECK ((daily >= 0));
alter table public.agents add constraint agents_max_concurrent_check CHECK (((max_concurrent >= 1) AND (max_concurrent <= 50)));
alter table public.agents add constraint agents_monthly_check CHECK (((monthly IS NULL) OR (monthly >= 0)));
alter table public.agents add constraint agents_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 60)));
alter table public.agents add constraint agents_per_tx_check CHECK ((per_tx >= 0));
alter table public.agents add constraint agents_weekly_check CHECK (((weekly IS NULL) OR (weekly >= 0)));
alter table public.owner_provider_keys add constraint owner_provider_keys_provider_check CHECK ((provider = ANY (ARRAY['anthropic'::text, 'openai'::text, 'google'::text, 'openrouter'::text])));
alter table public.owners add constraint owners_currency_chk CHECK ((currency = ANY (ARRAY['JPY'::text, 'USD'::text])));
alter table public.owners add constraint owners_lang_chk CHECK ((lang = ANY (ARRAY['ja'::text, 'en'::text])));
alter table public.passkey_challenges add constraint passkey_challenges_kind_check CHECK ((kind = ANY (ARRAY['reg'::text, 'auth'::text])));
alter table public.provider_keys add constraint provider_keys_provider_check CHECK ((provider = ANY (ARRAY['anthropic'::text, 'openai'::text, 'google'::text, 'openrouter'::text])));
alter table public.requests add constraint requests_amount_check CHECK ((amount > (0)::numeric));
alter table public.requests add constraint requests_merchant_check CHECK (((char_length(merchant) >= 1) AND (char_length(merchant) <= 200)));
alter table public.requests add constraint requests_recurring_check CHECK ((recurring = ANY (ARRAY['week'::text, 'month'::text, 'year'::text, 'unknown'::text])));
alter table public.requests add constraint requests_status_check CHECK ((status = ANY (ARRAY['approved_auto'::text, 'pending'::text, 'approved'::text, 'denied'::text, 'rejected'::text, 'expired'::text])));
alter table public.settings add constraint settings_id_check CHECK ((id = 1));
alter table public.site_stats add constraint site_stats_event_check CHECK ((event = ANY (ARRAY['visit'::text, 'start_click'::text, 'signup'::text])));
alter table public.agents add constraint agents_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES owners(id);
alter table public.oauth_requests add constraint oauth_requests_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE;
alter table public.oauth_requests add constraint oauth_requests_client_id_fkey FOREIGN KEY (client_id) REFERENCES oauth_clients(client_id) ON DELETE CASCADE;
alter table public.oauth_tokens add constraint oauth_tokens_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE;
alter table public.oauth_tokens add constraint oauth_tokens_client_id_fkey FOREIGN KEY (client_id) REFERENCES oauth_clients(client_id) ON DELETE CASCADE;
alter table public.owner_device_keys add constraint owner_device_keys_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES owners(id) ON DELETE CASCADE;
alter table public.owner_passkeys add constraint owner_passkeys_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES owners(id) ON DELETE CASCADE;
alter table public.owner_provider_keys add constraint owner_provider_keys_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES owners(id);
alter table public.passkey_challenges add constraint passkey_challenges_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES owners(id) ON DELETE CASCADE;
alter table public.proxy_inflight add constraint proxy_inflight_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE;
alter table public.push_subs add constraint push_subs_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES owners(id);
alter table public.requests add constraint requests_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE;

-- indexes
CREATE INDEX agents_owner ON public.agents USING btree (owner_id);
CREATE INDEX oauth_tokens_agent ON public.oauth_tokens USING btree (agent_id);
CREATE INDEX owner_device_keys_owner ON public.owner_device_keys USING btree (owner_id);
CREATE INDEX owner_passkeys_owner ON public.owner_passkeys USING btree (owner_id);
CREATE INDEX proxy_inflight_agent ON public.proxy_inflight USING btree (agent_id);
CREATE INDEX proxy_inflight_open ON public.proxy_inflight USING btree (agent_id) WHERE (settled_at IS NULL);
CREATE INDEX push_subs_owner ON public.push_subs USING btree (owner_id);
CREATE INDEX requests_agent_created ON public.requests USING btree (agent_id, created_at DESC);
CREATE INDEX requests_agent_day ON public.requests USING btree (agent_id, day);
CREATE UNIQUE INDEX requests_agent_idem_key ON public.requests USING btree (agent_id, idem_key) WHERE (idem_key IS NOT NULL);
CREATE INDEX requests_created ON public.requests USING btree (created_at DESC);
CREATE INDEX requests_status ON public.requests USING btree (status) WHERE (status = 'pending'::text);

-- rls
alter table public.agents enable row level security;
alter table public.oauth_clients enable row level security;
alter table public.oauth_requests enable row level security;
alter table public.oauth_tokens enable row level security;
alter table public.owner_device_keys enable row level security;
alter table public.owner_passkeys enable row level security;
alter table public.owner_provider_keys enable row level security;
alter table public.owners enable row level security;
alter table public.passkey_challenges enable row level security;
alter table public.prices enable row level security;
alter table public.provider_keys enable row level security;
alter table public.proxy_inflight enable row level security;
alter table public.push_subs enable row level security;
alter table public.requests enable row level security;
alter table public.settings enable row level security;
alter table public.site_stats enable row level security;
alter table public.sync_jobs enable row level security;

-- functions
CREATE OR REPLACE FUNCTION public.app_archive_agent(p_owner_key text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  update agents set archived = true, active = false,
    key_hash = encode(extensions.digest(extensions.gen_random_bytes(32), 'sha256'), 'hex')
  where id = p_id and owner_id = o.id and not archived;
  if not found then return jsonb_build_object('error','agent_not_found'); end if;
  update requests set status = 'expired', note = 'AIが削除されたため失効', decided_at = now(), token_hash = null
  where agent_id = p_id and status = 'pending';
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_create_agent(p_owner_key text, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare o owners; k text := 'sbk_' || encode(extensions.gen_random_bytes(24), 'hex'); nid uuid;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if (select count(*) from agents where owner_id = o.id and not archived) >= 20 then return jsonb_build_object('error','too_many_agents'); end if;
  insert into agents (owner_id, name, key_hash, key_hint, per_tx, daily, auto_approve, merchants)
  values (o.id, left(coalesce(nullif(btrim(p_name),''),'AI'), 60), encode(extensions.digest(k, 'sha256'), 'hex'), left(k, 10) || '…',
    greatest(0, least(coalesce(p_per_tx,0), 100000000)), greatest(0, least(coalesce(p_daily,0), 100000000)), greatest(0, least(coalesce(p_auto,0), 100000000)),
    array(select left(btrim(m), 200) from unnest(coalesce(p_merchants, '{}')) m where btrim(m) <> '' limit 50))
  returning id into nid;
  return jsonb_build_object('ok', true, 'id', nid, 'agent_key', k);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_dashboard(p_owner_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  perform sb_expire();
  return jsonb_build_object(
    'kill', o.kill,
    'ntfy_topic', o.ntfy_topic,
    'push_count', (select count(*) from push_subs where owner_id = o.id and active),
    'usd_jpy', (select usd_jpy from settings where id = 1),
    'providers', coalesce((select jsonb_object_agg(provider, hint) from owner_provider_keys where owner_id = o.id and enabled), '{}'::jsonb),
    'today', (now() at time zone o.tz)::date,
    'tz', o.tz, 'tz_set', o.tz_set,
    'agents', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'key_hint', a.key_hint,
        'per_tx', a.per_tx, 'daily', a.daily, 'auto', a.auto_approve, 'merchants', a.merchants, 'active', a.active,
        'weekly', a.weekly, 'known_only', a.auto_known_only, 'max_concurrent', a.max_concurrent, 'monthly', a.monthly,
        'week_used', sb_usage_since(a.id, sb_week_start(a.id)), 'month_used', sb_usage_since(a.id, sb_month_start(a.id)),
        'spent', u.spent, 'reserved', u.reserved) order by a.created_at)
      from agents a cross join lateral sb_usage(a.id) u where a.owner_id = o.id and not a.archived), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'agent_id', r.agent_id, 'merchant', r.merchant,
        'amount', r.amount, 'reason', r.reason, 'status', r.status, 'note', r.note, 'created_at', r.created_at, 'source', r.source)
        order by r.created_at desc)
      from (select r.* from requests r join agents a on a.id = r.agent_id where a.owner_id = o.id and not a.archived
            order by r.created_at desc limit 150) r), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.app_decide(p_owner_key text, p_id bigint, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners; r requests;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  perform sb_expire();
  update requests set status = case when p_approve then 'approved' else 'rejected' end,
    note = case when p_approve then '人間が承認' else '人間が却下' end, decided_at = now(), token_hash = null
  where id = p_id and status = 'pending' and agent_id in (select id from agents where owner_id = o.id)
  returning * into r;
  if r.id is null then return jsonb_build_object('error','not_pending'); end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'status', r.status);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_oauth_decide(p_owner_key text, p_req text, p_agent uuid, p_new_name text, p_daily integer, p_auto integer, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare o owners; r oauth_requests; aid uuid; code text; created jsonb; sep text;
begin
  select * into r from oauth_requests where id = p_req and not used and created_at > now() - interval '30 minutes' for update;
  if r.id is null then return jsonb_build_object('error','request_expired'); end if;
  sep := case when position('?' in r.redirect_uri) > 0 then '&' else '?' end;
  if not coalesce(p_approve, false) then
    update oauth_requests set used = true where id = r.id;
    return jsonb_build_object('redirect', r.redirect_uri || sep || 'error=access_denied'
      || case when r.state is not null then '&state=' || replace(replace(replace(r.state,'%','%25'),'&','%26'),'#','%23') else '' end);
  end if;
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if p_agent is not null then
    select id into aid from agents where id = p_agent and owner_id = o.id and not archived;
    if aid is null then return jsonb_build_object('error','agent_not_found'); end if;
  else
    created := app_create_agent(p_owner_key, coalesce(nullif(btrim(p_new_name),''), 'AI'), 5000, p_daily, p_auto, '{}');
    if created ? 'error' then return created; end if;
    aid := (created->>'id')::uuid;
  end if;
  code := encode(extensions.gen_random_bytes(24), 'hex');
  update oauth_requests set agent_id = aid, code_hash = sb_h(code), code_expires = now() + interval '5 minutes', used = true where id = r.id;
  return jsonb_build_object('redirect', r.redirect_uri || sep || 'code=' || code
    || case when r.state is not null then '&state=' || replace(replace(replace(replace(r.state,'%','%25'),'&','%26'),'#','%23'),'+','%2B') else '' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_oauth_info(p_owner_key text, p_req text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners; r oauth_requests; c oauth_clients;
begin
  select * into r from oauth_requests where id = p_req and not used and created_at > now() - interval '30 minutes';
  if r.id is null then return jsonb_build_object('error','request_expired'); end if;
  select * into c from oauth_clients where client_id = r.client_id;
  o := app_owner(p_owner_key);
  return jsonb_build_object('client_name', c.client_name,
    'redirect_host', substring(r.redirect_uri from '^[a-z][a-z0-9+.-]*://([^/?#]+)'),
    'signed_in', o.id is not null,
    'agents', case when o.id is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'daily', a.daily) order by a.created_at)
       from agents a where a.owner_id = o.id and not a.archived), '[]'::jsonb) end);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_owner(p_key text)
 RETURNS owners
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with h as (select encode(extensions.digest(coalesce(p_key,''), 'sha256'), 'hex') v)
  select o.* from owners o, h where o.key_hash = h.v
  union all
  select o.* from owner_device_keys d join owners o on o.id = d.owner_id, h where d.key_hash = h.v
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.app_owner_prefs(p_owner_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  return sb_owner_prefs(o.id);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_push_subscribe(p_owner_key text, p_endpoint text, p_p256dh text, p_auth text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if p_endpoint !~ '^https://' or char_length(p_endpoint) > 1000 or coalesce(p_p256dh,'') = '' or coalesce(p_auth,'') = '' then
    return jsonb_build_object('error','bad_subscription'); end if;
  insert into push_subs (endpoint, owner_id, p256dh, auth, active) values (p_endpoint, o.id, p_p256dh, p_auth, true)
  on conflict (endpoint) do update set owner_id = excluded.owner_id, p256dh = excluded.p256dh, auth = excluded.auth, active = true;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_push_unsubscribe(p_owner_key text, p_endpoint text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  update push_subs set active = false where endpoint = p_endpoint and owner_id = o.id;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_rotate_key(p_owner_key text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare o owners; k text := 'sbk_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  update agents set key_hash = encode(extensions.digest(k, 'sha256'), 'hex'), key_hint = left(k, 10) || '…'
  where id = p_id and owner_id = o.id and not archived;
  if not found then return jsonb_build_object('error','agent_not_found'); end if;
  return jsonb_build_object('ok', true, 'agent_key', k);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_set_currency(p_owner_key text, p_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if p_currency not in ('JPY','USD') then return jsonb_build_object('error','bad_currency'); end if;
  update owners set currency = p_currency where id = o.id;
  return jsonb_build_object('ok', true, 'currency', p_currency);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_set_kill(p_owner_key text, p_kill boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  update owners set kill = coalesce(p_kill, false) where id = o.id;
  return jsonb_build_object('ok', true, 'kill', coalesce(p_kill, false));
end $function$
;

CREATE OR REPLACE FUNCTION public.app_set_lang(p_owner_key text, p_lang text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if p_lang not in ('ja','en') then return jsonb_build_object('error','bad_lang'); end if;
  update owners set lang = p_lang where id = o.id;
  return jsonb_build_object('ok', true, 'lang', p_lang);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_set_ntfy(p_owner_key text, p_topic text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if p_topic is not null and p_topic !~ '^[A-Za-z0-9_-]{16,64}$' then return jsonb_build_object('error','bad_topic'); end if;
  update owners set ntfy_topic = p_topic where id = o.id;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_set_provider_key(p_owner_key text, p_provider text, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
declare o owners; old uuid; sid uuid; k text := btrim(coalesce(p_key,''));
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if sb_merchant_name(p_provider) is null then return jsonb_build_object('error','bad_provider'); end if;
  select secret_id into old from owner_provider_keys where owner_id = o.id and provider = p_provider;
  if k = '' then
    if old is not null then
      perform vault.update_secret(old, 'unset');
      update owner_provider_keys set enabled = false, hint = '', updated_at = now() where owner_id = o.id and provider = p_provider;
    end if;
    return jsonb_build_object('ok', true, 'removed', true);
  end if;
  if char_length(k) < 20 or char_length(k) > 400 or k ~ '\s' then return jsonb_build_object('error','bad_key'); end if;
  if old is not null then
    perform vault.update_secret(old, k);
    update owner_provider_keys set hint = left(k, 7) || '…' || right(k, 4), enabled = true, updated_at = now() where owner_id = o.id and provider = p_provider;
  else
    sid := vault.create_secret(k, 'saifuban_' || o.id || '_' || p_provider || '_' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint);
    insert into owner_provider_keys (owner_id, provider, secret_id, hint) values (o.id, p_provider, sid, left(k, 7) || '…' || right(k, 4));
  end if;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_set_tz(p_owner_key text, p_tz text, p_auto boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if p_tz is null or not exists (select 1 from pg_timezone_names where name = p_tz) then return jsonb_build_object('error','bad_timezone'); end if;
  if p_auto and o.tz_set then return jsonb_build_object('ok', true, 'tz', o.tz, 'changed', false); end if;
  update owners set tz = p_tz, tz_set = true where id = o.id;
  if p_tz <> o.tz then
    update requests r set day = (r.created_at at time zone p_tz)::date
      from agents a where a.id = r.agent_id and a.owner_id = o.id and r.created_at > now() - interval '40 days';
  end if;
  return jsonb_build_object('ok', true, 'tz', p_tz, 'changed', p_tz <> o.tz);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_signup()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare k text := 'sbo_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into owners (key_hash, key_hint) values (encode(extensions.digest(k, 'sha256'), 'hex'), left(k, 10) || '…');
  return jsonb_build_object('ok', true, 'owner_key', k);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_track(p_event text, p_src text, p_lang text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e text := lower(coalesce(p_event,''));
  s text := lower(regexp_replace(coalesce(nullif(p_src,''),'direct'), '[^a-z0-9._-]', '', 'gi'));
  l text := case when p_lang = 'en' then 'en' else 'ja' end;
begin
  -- 訪問 → はじめる → 登録 → AIを作った → 設定をコピーした → APIキーを預けた → パスキー登録 → お試し
  if e not in ('visit','start_click','signup','agent_created','copy_setup','key_stored','passkey_added','passkey_login','faq_open') then
    return jsonb_build_object('error','bad_event');
  end if;
  s := left(regexp_replace(s, '^www\\.', ''), 60);
  if s = '' then s := 'direct'; end if;
  insert into site_stats(day, event, src, lang, n)
  values ((now() at time zone 'Asia/Tokyo')::date, e, s, l, 1)
  on conflict (day, event, src, lang) do update set n = site_stats.n + 1;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_update_agent(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  update agents set name = left(coalesce(nullif(btrim(p_name),''), name), 60),
    per_tx = greatest(0, least(coalesce(p_per_tx,0), 100000000)), daily = greatest(0, least(coalesce(p_daily,0), 100000000)),
    auto_approve = greatest(0, least(coalesce(p_auto,0), 100000000)),
    merchants = array(select left(btrim(m), 200) from unnest(coalesce(p_merchants, '{}')) m where btrim(m) <> '' limit 50),
    active = coalesce(p_active, active)
  where id = p_id and owner_id = o.id and not archived;
  if not found then return jsonb_build_object('error','agent_not_found'); end if;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.app_update_agent_v2(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  r := app_update_agent(p_owner_key, p_id, p_name, p_per_tx, p_daily, p_auto, p_merchants, p_active);
  if r ? 'error' then return r; end if;
  update agents set weekly = nullif(greatest(0, least(coalesce(p_weekly,0), 100000000)), 0),
                    monthly = nullif(greatest(0, least(coalesce(p_monthly,0), 100000000)), 0)
   where id = p_id;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.app_update_agent_v3(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer, p_known_only boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  r := app_update_agent_v2(p_owner_key, p_id, p_name, p_per_tx, p_daily, p_auto, p_merchants, p_active, p_weekly, p_monthly);
  if r ? 'error' then return r; end if;
  if p_known_only is not null then update agents set auto_known_only = p_known_only where id = p_id; end if;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.app_update_agent_v4(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer, p_known_only boolean, p_max_concurrent integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  r := app_update_agent_v3(p_owner_key, p_id, p_name, p_per_tx, p_daily, p_auto, p_merchants, p_active, p_weekly, p_monthly, p_known_only);
  if r ? 'error' then return r; end if;
  if p_max_concurrent is not null then update agents set max_concurrent = greatest(1, least(p_max_concurrent, 50)) where id = p_id; end if;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.oauth_authorize_start(p_client text, p_redirect text, p_challenge text, p_method text, p_state text, p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c oauth_clients; rid text := encode(extensions.gen_random_bytes(18), 'hex');
begin
  select * into c from oauth_clients where client_id = p_client;
  if c.client_id is null then return jsonb_build_object('error','invalid_client'); end if;
  if not oauth_redirect_ok(c.redirect_uris, p_redirect) then return jsonb_build_object('error','invalid_redirect_uri'); end if;
  if coalesce(p_method,'') <> 'S256' or coalesce(p_challenge,'') !~ '^[A-Za-z0-9_-]{43,128}$' then
    return jsonb_build_object('error','invalid_request', 'redirect', p_redirect, 'description', 'PKCE S256 is required'); end if;
  delete from oauth_requests where created_at < now() - interval '1 day';
  insert into oauth_requests (id, client_id, redirect_uri, code_challenge, state, scope)
  values (rid, p_client, p_redirect, p_challenge, left(p_state, 1000), left(p_scope, 200));
  return jsonb_build_object('request_id', rid);
end $function$
;

CREATE OR REPLACE FUNCTION public.oauth_issue(p_agent uuid, p_client text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare at text := 'sbk_oa_' || encode(extensions.gen_random_bytes(24), 'hex');
        rt text := 'sbr_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into oauth_tokens (agent_id, client_id, access_hash, refresh_hash, access_expires, refresh_expires)
  values (p_agent, p_client, sb_h(at), sb_h(rt), now() + interval '1 day', now() + interval '180 days');
  return jsonb_build_object('access_token', at, 'token_type', 'Bearer', 'expires_in', 86400, 'refresh_token', rt, 'scope', 'saifuban');
end $function$
;

CREATE OR REPLACE FUNCTION public.oauth_redirect_ok(p_allowed text[], p_uri text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select exists (select 1 from unnest(p_allowed) u where u = p_uri
    or (u ~ '^http://(localhost|127\.0\.0\.1)(:\d+)?/' and p_uri ~ '^http://(localhost|127\.0\.0\.1)(:\d+)?/'
        and regexp_replace(u, '^http://(localhost|127\.0\.0\.1)(:\d+)?', '') = regexp_replace(p_uri, '^http://(localhost|127\.0\.0\.1)(:\d+)?', '')))
$function$
;

CREATE OR REPLACE FUNCTION public.oauth_register(p_redirect_uris text[], p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cid text := 'sbc_' || encode(extensions.gen_random_bytes(16), 'hex'); u text;
begin
  if p_redirect_uris is null or array_length(p_redirect_uris,1) is null or array_length(p_redirect_uris,1) > 10 then
    return jsonb_build_object('error','invalid_redirect_uri'); end if;
  foreach u in array p_redirect_uris loop
    if char_length(u) > 500 or not (u ~ '^https://' or u ~ '^http://(localhost|127\.0\.0\.1)(:\d+)?/' or u ~ '^[a-z][a-z0-9+.-]*:/') then
      return jsonb_build_object('error','invalid_redirect_uri'); end if;
  end loop;
  insert into oauth_clients (client_id, client_name, redirect_uris) values (cid, left(coalesce(p_name,''), 100), p_redirect_uris);
  return jsonb_build_object('client_id', cid);
end $function$
;

CREATE OR REPLACE FUNCTION public.oauth_revoke_agent(p_agent uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ update oauth_tokens set revoked = true where agent_id = p_agent $function$
;

CREATE OR REPLACE FUNCTION public.oauth_revoke_on_rotate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.key_hash is distinct from old.key_hash or (new.archived and not old.archived) then
    update oauth_tokens set revoked = true where agent_id = new.id;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.oauth_token_code(p_client text, p_code text, p_verifier text, p_redirect text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r oauth_requests; ch text;
begin
  select * into r from oauth_requests where code_hash = sb_h(p_code) for update;
  if r.id is null or r.code_expires < now() or r.agent_id is null then return jsonb_build_object('error','invalid_grant'); end if;
  update oauth_requests set code_hash = null where id = r.id;  -- 1回だけ
  if p_client is not null and p_client <> r.client_id then return jsonb_build_object('error','invalid_grant'); end if;
  if p_redirect is not null and p_redirect <> r.redirect_uri then return jsonb_build_object('error','invalid_grant'); end if;
  ch := rtrim(translate(encode(extensions.digest(coalesce(p_verifier,''), 'sha256'), 'base64'), '+/', '-_'), '=');
  if ch <> r.code_challenge then return jsonb_build_object('error','invalid_grant'); end if;
  if exists (select 1 from agents where id = r.agent_id and archived) then return jsonb_build_object('error','invalid_grant'); end if;
  return oauth_issue(r.agent_id, r.client_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.oauth_token_refresh(p_client text, p_refresh text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare t oauth_tokens;
begin
  select * into t from oauth_tokens where refresh_hash = sb_h(p_refresh) for update;
  if t.id is null or t.revoked or t.refresh_expires < now() then return jsonb_build_object('error','invalid_grant'); end if;
  if p_client is not null and p_client <> t.client_id then return jsonb_build_object('error','invalid_grant'); end if;
  if exists (select 1 from agents where id = t.agent_id and archived) then return jsonb_build_object('error','invalid_grant'); end if;
  update oauth_tokens set revoked = true, refresh_hash = null where id = t.id;  -- 使い回し防止(ローテーション)
  return oauth_issue(t.agent_id, t.client_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.oauth_token_valid(p_token text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from oauth_tokens t join agents a on a.id = t.agent_id
    where t.access_hash = sb_h(p_token) and not t.revoked and t.access_expires > now() and not a.archived)
$function$
;

CREATE OR REPLACE FUNCTION public.sb_agent_by_key(p_key text)
 RETURNS agents
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select * from agents where key_hash = sb_h(p_key)
  union all
  select a.* from oauth_tokens t join agents a on a.id = t.agent_id
   where p_key like 'sbk_oa_%' and t.access_hash = sb_h(p_key) and not t.revoked and t.access_expires > now()
  limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.sb_agent_tz(p_agent uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select o.tz from agents a join owners o on o.id = a.owner_id where a.id = p_agent), 'Asia/Tokyo')
$function$
;

CREATE OR REPLACE FUNCTION public.sb_budget(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a agents; u record; w numeric; m numeric;
begin
  a := sb_agent_by_key(p_key);
  if a.id is null or a.archived then return jsonb_build_object('error','invalid_agent_key'); end if;
  perform sb_expire();
  select * into u from sb_usage(a.id);
  w := sb_usage_since(a.id, sb_week_start(a.id)); m := sb_usage_since(a.id, sb_month_start(a.id));
  return jsonb_build_object('agent', a.name, 'can_spend', a.active and not sb_killed(a.owner_id),
    'per_transaction_limit_jpy', a.per_tx, 'daily_budget_jpy', a.daily,
    'auto_approve_up_to_jpy', a.auto_approve, 'auto_approve_known_merchants_only', a.auto_known_only, 'max_concurrent_api_requests', a.max_concurrent, 'spent_today_jpy', round(u.spent),
    'pending_today_jpy', round(u.reserved), 'remaining_today_jpy', floor(greatest(0, a.daily - u.spent - u.reserved)),
    'budget_resets_at', 'midnight ' || sb_agent_tz(a.id),
    'weekly_budget_jpy', nullif(a.weekly, 0), 'used_this_week_jpy', round(w),
    'remaining_this_week_jpy', case when coalesce(a.weekly,0) > 0 then floor(greatest(0, a.weekly - w)) end,
    'monthly_budget_jpy', nullif(a.monthly, 0), 'used_this_month_jpy', round(m),
    'remaining_this_month_jpy', case when coalesce(a.monthly,0) > 0 then floor(greatest(0, a.monthly - m)) end,
    'subscriptions', '定期購入は金額に関係なく持ち主の承認が必要 / subscriptions always need the owner''s approval',
    'allowed_merchants', case when coalesce(array_length(a.merchants,1),0) = 0 then to_jsonb('すべて(予算と承認ルールの範囲内)'::text) else to_jsonb(a.merchants) end);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_create_agent(p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare k text := 'sbk_' || encode(extensions.gen_random_bytes(24), 'hex'); nid uuid;
begin
  insert into agents (name, key_hash, key_hint, per_tx, daily, auto_approve, merchants)
  values (btrim(p_name), encode(extensions.digest(k, 'sha256'), 'hex'), left(k, 10) || '…',
    greatest(0, p_per_tx), greatest(0, p_daily), greatest(0, p_auto),
    array(select btrim(m) from unnest(p_merchants) m where btrim(m) <> ''))
  returning id into nid;
  return jsonb_build_object('ok', true, 'id', nid, 'agent_key', k);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform sb_expire();
  return jsonb_build_object(
    'kill', (select kill from settings where id = 1),
    'ntfy_topic', (select ntfy_topic from settings where id = 1),
    'usd_jpy', (select usd_jpy from settings where id = 1),
    'providers', coalesce((select jsonb_object_agg(provider, hint) from provider_keys where enabled), '{}'::jsonb),
    'today', (now() at time zone 'Asia/Tokyo')::date,
    'agents', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'key_hint', a.key_hint,
        'per_tx', a.per_tx, 'daily', a.daily, 'auto', a.auto_approve, 'merchants', a.merchants, 'active', a.active,
        'spent', u.spent, 'reserved', u.reserved) order by a.created_at)
      from agents a cross join lateral sb_usage(a.id) u), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'agent_id', r.agent_id, 'merchant', r.merchant,
        'amount', r.amount, 'reason', r.reason, 'status', r.status, 'note', r.note, 'created_at', r.created_at, 'source', r.source)
        order by r.created_at desc)
      from (select * from requests order by created_at desc limit 150) r), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_decide(p_id bigint, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r requests;
begin
  perform sb_expire();
  update requests set status = case when p_approve then 'approved' else 'rejected' end,
    note = case when p_approve then '人間が承認' else '人間が却下' end, decided_at = now(), token_hash = null
  where id = p_id and status = 'pending' returning * into r;
  if r.id is null then return jsonb_build_object('error','not_pending'); end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'status', r.status);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_decide_token(p_id bigint, p_token text, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r requests; oid uuid;
begin
  perform sb_expire();
  update requests set status = case when p_approve then 'approved' else 'rejected' end,
    note = case when p_approve then '人間が承認(通知から)' else '人間が却下(通知から)' end,
    decided_at = now(), token_hash = null
  where id = p_id and status = 'pending' and token_hash is not null
    and token_hash = encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
  returning * into r;
  if r.id is null then return jsonb_build_object('error','not_pending'); end if;
  select owner_id into oid from agents where id = r.agent_id;
  return jsonb_build_object('ok', true, 'status', r.status, 'merchant', r.merchant, 'amount', r.amount, 'owner_id', oid);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_delete_agent(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  delete from agents where id = p_id;
  select jsonb_build_object('ok', true);
$function$
;

CREATE OR REPLACE FUNCTION public.sb_expire()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update requests set status = 'expired', note = '24時間承認されず失効', decided_at = now()
  where status = 'pending' and created_at < now() - interval '24 hours';
$function$
;

CREATE OR REPLACE FUNCTION public.sb_fx_apply(p_body jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r numeric;
begin
  begin r := (p_body->'rates'->>'JPY')::numeric; exception when others then return null; end;
  if r is null or r < 50 or r > 500 then return null; end if;   -- おかしな値は使わない
  update settings set usd_jpy = round(r, 2), usd_jpy_updated_at = now() where id = 1;
  return round(r, 2);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_h(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$ select encode(extensions.digest(coalesce(t,''), 'sha256'), 'hex') $function$
;

CREATE OR REPLACE FUNCTION public.sb_history(p_key text, p_merchant text, p_days integer, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a agents; d int := least(greatest(coalesce(p_days, 30), 1), 365); n int := least(greatest(coalesce(p_limit, 20), 1), 100);
  mer text := nullif(btrim(coalesce(p_merchant,'')), '');
begin
  a := sb_agent_by_key(p_key);
  if a.id is null then return jsonb_build_object('error','invalid_agent_key'); end if;
  perform sb_expire();
  return jsonb_build_object('days', d, 'merchant_filter', mer, 'payments', coalesce((
    select jsonb_agg(x order by x->>'requested_at' desc) from (
      select jsonb_build_object('request_id', r.id, 'merchant', r.merchant, 'amount_jpy', r.amount,
        'status', sb_public_status(r.status), 'reason_for_status', r.note, 'agent_reason', r.reason,
        'recurring', coalesce(r.recurring, 'none'), 'requested_at', r.created_at, 'decided_at', r.decided_at,
        'paid_with_token', r.redeemed_at is not null) x
      from requests r
      where r.agent_id = a.id and r.created_at > now() - make_interval(days => d)
        and (mer is null or r.merchant ilike '%' || mer || '%')
      order by r.created_at desc limit n) s), '[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_inflight_jpy(p_agent uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(reserved_jpy), 0)::numeric from proxy_inflight
  where agent_id = p_agent and settled_at is null
$function$
;

CREATE OR REPLACE FUNCTION public.sb_issue_token(p_key text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a agents; r requests;
begin
  a := sb_agent_by_key(p_key);
  if a.id is null then return null; end if;
  select * into r from requests where id = p_id and agent_id = a.id;
  if r.id is null or r.status not in ('approved','approved_auto') then return null; end if;
  return jsonb_build_object(
    'payment_token', sb_token_for(r.id),
    'payment_token_expires_at', coalesce(r.decided_at, r.created_at) + interval '24 hours',
    'payment_token_used', r.redeemed_at is not null);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_key_prefs(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a agents;
begin
  a := sb_agent_by_key(p_key);
  return sb_owner_prefs(a.owner_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_killed(p_owner uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select kill from settings where id = 1), false)
      or coalesce((select kill from owners where id = p_owner), false);
$function$
;

CREATE OR REPLACE FUNCTION public.sb_looks_recurring(p_text text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(p_text,'') ~* '(subscri|サブスク|月額|年額|毎月|毎年|月々|月払|年払|定期購入|定期便|継続課金|自動更新|recurring|monthly|yearly|annual|per month|per year|/ ?mo\M|/ ?month|/ ?yr|/ ?year|renew|membership|メンバーシップ|会員プラン|プレミアムプラン|pro plan|plus plan|premium plan)'
$function$
;

CREATE OR REPLACE FUNCTION public.sb_max_output(p_provider text, p_model text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with m as (select case when p_provider = 'openrouter' then lower(coalesce(p_model, ''))
                         else regexp_replace(lower(coalesce(p_model, '')), '^(models/|[a-z0-9-]+/)', '') end as name)
  select p.max_output from prices p, m
   where p.provider = p_provider and p.model_prefix <> '' and p.max_output is not null
     and (m.name = p.model_prefix or (m.name like p.model_prefix || '-%' and substr(m.name, length(p.model_prefix) + 2, 1) ~ '[0-9]'))
   order by length(p.model_prefix) desc limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.sb_merchant_name(p_provider text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case p_provider when 'anthropic' then 'Anthropic API' when 'openai' then 'OpenAI API'
    when 'google' then 'Google Gemini API' when 'openrouter' then 'OpenRouter' end;
$function$
;

CREATE OR REPLACE FUNCTION public.sb_merchant_ok(p_list text[], p_mer text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(array_length(p_list, 1), 0) = 0
      or exists (select 1 from unnest(p_list) m where lower(btrim(m)) = lower(btrim(p_mer)));
$function$
;

CREATE OR REPLACE FUNCTION public.sb_money_for(p_owner uuid, p_jpy numeric)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when coalesce((select currency from owners where id = p_owner), 'JPY') = 'USD'
    then '$' || to_char(round(p_jpy / nullif((select usd_jpy from settings where id = 1), 0), 2), 'FM999,999,990.00')
    else to_char(round(p_jpy), 'FM999,999,999,990') || '円' end
$function$
;

CREATE OR REPLACE FUNCTION public.sb_month_start()
 RETURNS date
 LANGUAGE sql
 STABLE
AS $function$
  select date_trunc('month', (now() at time zone 'Asia/Tokyo'))::date $function$
;

CREATE OR REPLACE FUNCTION public.sb_month_start(p_agent uuid)
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select date_trunc('month', now() at time zone sb_agent_tz(p_agent))::date $function$
;

CREATE OR REPLACE FUNCTION public.sb_notify_prepare(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r requests; a agents; topic text; t text := encode(extensions.gen_random_bytes(24),'hex'); targets jsonb; pr jsonb;
begin
  select * into r from requests where id = p_id and status = 'pending';
  if r.id is null then return jsonb_build_object('skip', true); end if;
  select * into a from agents where id = r.agent_id;
  topic := sb_owner_topic(a.owner_id);
  targets := case when a.owner_id is null then '[]'::jsonb else sb_push_targets(a.owner_id) end;
  if topic is null and jsonb_array_length(targets) = 0 then return jsonb_build_object('skip', true); end if;
  update requests set token_hash = encode(extensions.digest(t,'sha256'),'hex') where id = r.id;
  pr := sb_owner_prefs(a.owner_id);
  return jsonb_build_object('topic', topic, 'push', targets, 'token', t, 'id', r.id, 'agent', a.name, 'merchant', r.merchant,
    'amount', r.amount, 'reason', r.reason, 'note', r.note, 'app_url', (select app_url from settings where id = 1),
    'lang', pr->>'lang', 'currency', pr->>'currency', 'rate', (pr->>'rate')::numeric,
    'recurring', r.recurring, 'first_merchant', r.first_merchant);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_owner_lang(p_owner uuid)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select lang from owners where id = p_owner), 'ja')
$function$
;

CREATE OR REPLACE FUNCTION public.sb_owner_prefs(p_owner uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'lang', coalesce((select lang from owners where id = p_owner), 'ja'),
    'currency', coalesce((select currency from owners where id = p_owner), 'JPY'),
    'rate', (select usd_jpy from settings where id = 1))
$function$
;

CREATE OR REPLACE FUNCTION public.sb_owner_topic(p_owner uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when p_owner is null then (select ntfy_topic from settings where id = 1)
              else (select ntfy_topic from owners where id = p_owner) end;
$function$
;

CREATE OR REPLACE FUNCTION public.sb_period_block(a agents, p_add numeric, p_en boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w numeric; m numeric;
begin
  if coalesce(a.weekly, 0) > 0 then
    w := sb_usage_since(a.id, sb_week_start(a.id));
    if w + p_add > a.weekly then
      return case when p_en then format('Over weekly budget (%s)', sb_money_for(a.owner_id, a.weekly))
                  else format('1週間の予算(%s円)を超過', to_char(a.weekly, 'FM999,999,999,990')) end;
    end if;
  end if;
  if coalesce(a.monthly, 0) > 0 then
    m := sb_usage_since(a.id, sb_month_start(a.id));
    if m + p_add > a.monthly then
      return case when p_en then format('Over monthly budget (%s)', sb_money_for(a.owner_id, a.monthly))
                  else format('1か月の予算(%s円)を超過', to_char(a.monthly, 'FM999,999,999,990')) end;
    end if;
  end if;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_price_for(p_provider text, p_model text, p_prompt_tokens bigint DEFAULT 0, OUT input_per_mtok numeric, OUT output_per_mtok numeric, OUT matched text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m text := lower(coalesce(p_model, '')); pr prices; vendor text;
begin
  if p_provider = 'openrouter' then
    select * into pr from prices p where p.provider = 'openrouter' and p.model_prefix <> ''
      and (m = p.model_prefix or m like p.model_prefix || '-%' and substr(m, length(p.model_prefix) + 2, 1) ~ '[0-9]')
      order by length(p.model_prefix) desc limit 1;
    if pr.provider is not null then
      input_per_mtok := pr.input_per_mtok; output_per_mtok := pr.output_per_mtok; matched := pr.model_prefix; return;
    end if;
    vendor := split_part(m, '/', 1);
    if vendor in ('openai', 'anthropic', 'google') and position('/' in m) > 0 then
      select * into input_per_mtok, output_per_mtok, matched
        from sb_price_for(vendor, case when vendor = 'anthropic' then replace(split_part(m, '/', 2), '.', '-') else split_part(m, '/', 2) end, p_prompt_tokens);
      return;
    end if;
    matched := '(unknown: highest price)';
    select max(greatest(p.input_per_mtok, coalesce(p.long_input_per_mtok, 0))), max(greatest(p.output_per_mtok, coalesce(p.long_output_per_mtok, 0)))
      into input_per_mtok, output_per_mtok from prices p where p.provider <> 'openrouter';
    return;
  end if;
  m := regexp_replace(m, '^(models/|[a-z0-9-]+/)', '');
  select * into pr from prices p where p.provider = p_provider and p.model_prefix <> ''
    and (m = p.model_prefix or m like p.model_prefix || '-%' and substr(m, length(p.model_prefix) + 2, 1) ~ '[0-9]')
    order by length(p.model_prefix) desc limit 1;
  if pr.provider is not null then
    matched := pr.model_prefix;
    if pr.long_threshold is not null and coalesce(p_prompt_tokens, 0) > pr.long_threshold then
      input_per_mtok := coalesce(pr.long_input_per_mtok, pr.input_per_mtok); output_per_mtok := coalesce(pr.long_output_per_mtok, pr.output_per_mtok);
    else
      input_per_mtok := pr.input_per_mtok; output_per_mtok := pr.output_per_mtok;
    end if;
    return;
  end if;
  matched := '(unknown: highest ' || p_provider || ' price)';
  select max(greatest(p.input_per_mtok, coalesce(p.long_input_per_mtok, 0))), max(greatest(p.output_per_mtok, coalesce(p.long_output_per_mtok, 0)))
    into input_per_mtok, output_per_mtok from prices p where p.provider = p_provider;
  if input_per_mtok is null then
    select max(p.input_per_mtok), max(p.output_per_mtok) into input_per_mtok, output_per_mtok from prices p;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_prices_apply(p_body jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e jsonb; id text; prov text; model text; pi numeric; po numeric; mo integer; n int := 0;
begin
  for e in select * from jsonb_array_elements(p_body->'data') loop
    id := lower(e->>'id');
    if id is null or position('/' in id) = 0 then continue; end if;
    begin
      pi := round((e->'pricing'->>'prompt')::numeric * 1000000, 4); po := round((e->'pricing'->>'completion')::numeric * 1000000, 4);
    exception when others then continue; end;
    begin mo := nullif((e->'top_provider'->>'max_completion_tokens')::integer, 0); exception when others then mo := null; end;
    if pi is null or po is null or pi < 0 or po < 0 or pi > 1000 or po > 5000 then continue; end if;
    insert into prices (provider, model_prefix, input_per_mtok, output_per_mtok, max_output, source, updated_at)
    values ('openrouter', id, pi, po, mo, 'openrouter', now())
    on conflict (provider, model_prefix) do update set input_per_mtok = excluded.input_per_mtok, output_per_mtok = excluded.output_per_mtok,
      max_output = coalesce(excluded.max_output, prices.max_output), source = 'openrouter', updated_at = now()
    where excluded.input_per_mtok >= prices.input_per_mtok * 0.2 and excluded.output_per_mtok >= prices.output_per_mtok * 0.2;
    if id like '%:%' or id !~ '^(openai|anthropic|google)/' or pi <= 0 then n := n + 1; continue; end if;
    prov := split_part(id, '/', 1); model := split_part(id, '/', 2);
    if prov = 'anthropic' then model := replace(model, '.', '-'); end if;
    insert into prices (provider, model_prefix, input_per_mtok, output_per_mtok, max_output, source, updated_at)
    values (prov, model, pi, po, mo, 'openrouter', now())
    on conflict (provider, model_prefix) do update set input_per_mtok = excluded.input_per_mtok, output_per_mtok = excluded.output_per_mtok,
      max_output = coalesce(excluded.max_output, prices.max_output), source = 'openrouter', updated_at = now()
    where prices.source <> 'manual-pinned'
      and excluded.input_per_mtok >= prices.input_per_mtok * 0.2 and excluded.output_per_mtok >= prices.output_per_mtok * 0.2;
    n := n + 1;
  end loop;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_begin(p_key text, p_provider text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
declare a agents; u record; mer text; pk text; en boolean; pb text;
begin
  a := sb_agent_by_key(p_key);
  if a.id is null or a.archived then return jsonb_build_object('error','invalid_agent_key'); end if;
  en := coalesce((select lang from owners where id = a.owner_id), 'ja') = 'en';
  mer := sb_merchant_name(p_provider);
  if mer is null then return jsonb_build_object('error','bad_provider','lang', case when en then 'en' else 'ja' end); end if;
  select * into u from sb_usage(a.id);
  if sb_killed(a.owner_id) then return jsonb_build_object('error','blocked','lang', case when en then 'en' else 'ja' end,
    'reason', case when en then 'Emergency stop is on' else '緊急停止中' end); end if;
  if not a.active then return jsonb_build_object('error','blocked','lang', case when en then 'en' else 'ja' end,
    'reason', case when en then 'This AI is stopped' else 'このAIは停止中' end); end if;
  if not sb_merchant_ok(a.merchants, mer) then
    return jsonb_build_object('error','blocked','lang', case when en then 'en' else 'ja' end,
      'reason', case when en then mer || ' is not in the allowed merchants' else mer || ' は使ってよい支払先に入っていません' end); end if;
  if u.spent + u.reserved >= a.daily then
    return jsonb_build_object('error','blocked','lang', case when en then 'en' else 'ja' end,
      'reason', case when en then format('Over daily budget (%s)', sb_money_for(a.owner_id, a.daily))
                     else format('1日の予算(%s)を超過', sb_money_for(a.owner_id, a.daily)) end); end if;
  pb := sb_period_block(a, 0.000001, en);
  if pb is not null then return jsonb_build_object('error','blocked','lang', case when en then 'en' else 'ja' end, 'reason', pb); end if;
  if a.owner_id is not null then
    select ds.decrypted_secret into pk from owner_provider_keys p join vault.decrypted_secrets ds on ds.id = p.secret_id
      where p.owner_id = a.owner_id and p.provider = p_provider and p.enabled;
  else
    select ds.decrypted_secret into pk from provider_keys p join vault.decrypted_secrets ds on ds.id = p.secret_id
      where p.provider = p_provider and p.enabled;
  end if;
  if pk is null then return jsonb_build_object('error','no_provider_key','lang', case when en then 'en' else 'ja' end,
    'reason', case when en then 'No ' || mer || ' API key is stored in Saifuban' else mer || ' のAPIキーが預けられていません' end); end if;
  return jsonb_build_object('ok', true, 'agent_id', a.id, 'provider_key', pk, 'lang', case when en then 'en' else 'ja' end,
    'remaining_jpy', floor(a.daily - u.spent - u.reserved));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_begin_v3(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select sb_proxy_begin_v4(p_key, p_provider, p_model, p_in_est, p_out_max, 0)
$function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_begin_v4(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint, p_extra_usd numeric DEFAULT 0, p_choices integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
declare g jsonb; a agents; n int; en boolean; u record; rate numeric; est_usd numeric; est numeric; pb text; sid bigint;
  out_max bigint := p_out_max; filled boolean := false; ch integer := greatest(1, least(coalesce(p_choices, 1), 16));
begin
  a := sb_agent_by_key(p_key);
  if a.id is not null then
    perform 1 from agents where id = a.id for update;  -- 同じAIの呼び出しはここで一列に並ぶ
    perform sb_proxy_expire(a.id);
  end if;
  g := sb_proxy_begin(p_key, p_provider);
  if g ? 'error' then return g; end if;
  en := g->>'lang' = 'en';
  select count(*) into n from proxy_inflight where agent_id = a.id and settled_at is null;
  if n >= a.max_concurrent then
    return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429,
      'reason', case when en then format('Too many requests at once (limit %s). Wait for the others to finish', a.max_concurrent)
                     else format('同時に流せる数(%s件)を超えています。ほかの処理が終わるまで待ってください', a.max_concurrent) end);
  end if;
  if out_max < 0 then
    out_max := least(coalesce(sb_max_output(p_provider, p_model), 32768), 32768);
    filled := true;
  end if;
  select usd_jpy into rate from settings where id = 1;
  est_usd := sb_proxy_estimate_usd(p_provider, p_model, p_in_est, out_max * ch) + greatest(coalesce(p_extra_usd, 0), 0);
  est := greatest(1, ceil(est_usd * rate));
  select * into u from sb_usage(a.id);
  if u.spent + u.reserved + est > a.daily then
    -- ほかの呼び出しの予約が終われば収まる場合は「少し待って」(429)。AIはやり直せば通る。
    -- 使った額だけで収まらない場合は本当に予算切れ(403)。
    if u.reserved > 0 and u.spent + est <= a.daily then
      return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429,
        'reason', case when en then format('Other calls are still running and have %s reserved. This call (up to %s) fits once they finish. Retry shortly', sb_money_for(a.owner_id, u.reserved), sb_money_for(a.owner_id, est))
                       else format('ほかの呼び出しが%sを予約中です。終わればこの呼び出し(最大%s)は予算内に収まるので、少し待ってやり直してください', sb_money_for(a.owner_id, u.reserved), sb_money_for(a.owner_id, est)) end);
    end if;
    return jsonb_build_object('error','blocked','lang', g->>'lang',
      'reason', case when en then format('This call could cost up to %s, which would go over the daily budget (%s left)', sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(a.daily - u.spent - u.reserved))))
                     else format('この呼び出しは最大%sかかる可能性があり、1日の予算を超えます(残り%s)', sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(a.daily - u.spent - u.reserved)))) end);
  end if;
  pb := sb_period_block(a, est, en);
  if pb is not null then return jsonb_build_object('error','blocked','lang', g->>'lang', 'reason', pb); end if;
  insert into proxy_inflight (agent_id, reserved_jpy, provider, model) values (a.id, est, p_provider, p_model) returning id into sid;
  return g || jsonb_build_object('slot', sid, 'reserved_jpy', est, 'estimate_usd', est_usd,
    'out_max', case when filled then out_max end,
    'remaining_jpy', floor(a.daily - u.spent - u.reserved - est));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_begin_v5(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint, p_extra_usd numeric DEFAULT 0, p_choices integer DEFAULT 1, p_min_out bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
declare g jsonb; a agents; n int; en boolean; u record; rate numeric; est_usd numeric; est numeric; pb text; sid bigint;
  out_max bigint := p_out_max; filled boolean := false; ch integer := greatest(1, least(coalesce(p_choices, 1), 16));
  extra numeric := greatest(coalesce(p_extra_usd, 0), 0); avail numeric; lo bigint; hi bigint; mid bigint; orig bigint; shrunk boolean := false;
  reset_at timestamptz; period text;
begin
  a := sb_agent_by_key(p_key);
  if a.id is not null then
    perform 1 from agents where id = a.id for update;  -- 同じAIの呼び出しはここで一列に並ぶ
    perform sb_proxy_expire(a.id);
  end if;
  g := sb_proxy_begin(p_key, p_provider);
  if g ? 'error' then return g; end if;
  en := g->>'lang' = 'en';
  select count(*) into n from proxy_inflight where agent_id = a.id and settled_at is null;
  if n >= a.max_concurrent then
    return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'wait',
      'reason', case when en then format('Too many requests at once (limit %s). Wait for the others to finish', a.max_concurrent)
                     else format('同時に流せる数(%s件)を超えています。ほかの処理が終わるまで待ってください', a.max_concurrent) end);
  end if;
  -- 出力の上限が指定されていない(負の値): モデルの最大と 32,768 の小さい方。中継がこの値をリクエストに書き込む
  if out_max < 0 then
    out_max := least(coalesce(sb_max_output(p_provider, p_model), 32768), 32768);
    filled := true;
  end if;
  orig := out_max;
  select usd_jpy into rate from settings where id = 1;
  est_usd := sb_proxy_estimate_usd(p_provider, p_model, p_in_est, out_max * ch) + extra;
  est := greatest(1, ceil(est_usd * rate));
  select * into u from sb_usage(a.id);
  avail := a.daily - u.spent - u.reserved;
  if est > avail then
    -- 1) ほかの呼び出しの予約が終われば収まる → 少し待ってやり直してもらう(429、やり直してよい)
    if u.reserved > 0 and u.spent + est <= a.daily then
      return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'wait',
        'reason', case when en then format('Other calls are still running and have %s reserved. This call (up to %s) fits once they finish. Retry shortly', sb_money_for(a.owner_id, u.reserved), sb_money_for(a.owner_id, est))
                       else format('ほかの呼び出しが%sを予約中です。終わればこの呼び出し(最大%s)は予算内に収まるので、少し待ってやり直してください', sb_money_for(a.owner_id, u.reserved), sb_money_for(a.owner_id, est)) end);
    end if;
    -- 2) 出力の上限を残りの予算に収まるところまで縮めて通す(最低 p_min_out トークンは書ける場合だけ)
    if coalesce(p_min_out, 0) > 0 and out_max > p_min_out
       and ceil((sb_proxy_estimate_usd(p_provider, p_model, p_in_est, p_min_out * ch) + extra) * rate) <= avail then
      lo := p_min_out; hi := out_max - 1;
      while lo < hi loop
        mid := (lo + hi + 1) / 2;
        if ceil((sb_proxy_estimate_usd(p_provider, p_model, p_in_est, mid * ch) + extra) * rate) <= avail then lo := mid; else hi := mid - 1; end if;
      end loop;
      out_max := lo; shrunk := true;
      est_usd := sb_proxy_estimate_usd(p_provider, p_model, p_in_est, out_max * ch) + extra;
      est := greatest(1, ceil(est_usd * rate));
    else
      -- 3) 本当に予算切れ。リセットの時刻を付けて止める(やり直さない)
      reset_at := ((sb_today(a.id) + 1)::timestamp at time zone sb_agent_tz(a.id));
      return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'budget', 'period', 'daily', 'reset_at', reset_at,
        'reason', case when en then format('Daily budget reached: this call could cost up to %s and %s is left. Resets at %s', sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(avail))), to_char(reset_at at time zone sb_agent_tz(a.id), 'YYYY-MM-DD HH24:MI'))
                       else format('この呼び出しは最大%sかかる可能性があり、1日の予算を超えます(残り%s)。%sにリセットされます', sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(avail))), to_char(reset_at at time zone sb_agent_tz(a.id), 'MM/DD HH24:MI')) end);
    end if;
  end if;
  pb := sb_period_block(a, est, en);
  if pb is not null then
    period := case when pb ilike '%week%' or pb like '%週%' then 'weekly' else 'monthly' end;
    reset_at := (case when period = 'weekly' then sb_week_start(a.id) + 7 else (sb_month_start(a.id) + interval '1 month')::date end)::timestamp at time zone sb_agent_tz(a.id);
    return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'budget', 'period', period, 'reset_at', reset_at,
      'reason', pb || case when en then format('. Resets at %s', to_char(reset_at at time zone sb_agent_tz(a.id), 'YYYY-MM-DD HH24:MI'))
                       else format('。%sにリセットされます', to_char(reset_at at time zone sb_agent_tz(a.id), 'MM/DD HH24:MI')) end);
  end if;
  insert into proxy_inflight (agent_id, reserved_jpy, provider, model) values (a.id, est, p_provider, p_model) returning id into sid;
  return g || jsonb_build_object('slot', sid, 'reserved_jpy', est, 'estimate_usd', est_usd,
    'out_max', case when filled or shrunk then out_max end,
    'shrunk_from', case when shrunk then orig end,
    'remaining_jpy', floor(a.daily - u.spent - u.reserved - est));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_charge(p_agent uuid, p_provider text, p_model text, p_in bigint, p_out bigint, p_cache_write bigint, p_cache_read bigint, p_cost_usd numeric, p_note text DEFAULT NULL::text, p_day date DEFAULT NULL::date, p_extra_usd numeric DEFAULT 0, p_extra_note text DEFAULT NULL::text, OUT rid bigint, OUT jpy numeric)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pp record; rate numeric; usd numeric; how text; ex numeric := greatest(coalesce(p_extra_usd, 0), 0);
begin
  select usd_jpy into rate from settings where id = 1;
  if p_cost_usd is not null and p_cost_usd >= 0 then usd := p_cost_usd; how := '実費';
  else
    select * into pp from sb_price_for(p_provider, p_model, coalesce(p_in,0) + coalesce(p_cache_write,0) + coalesce(p_cache_read,0));
    usd := (coalesce(p_in,0) * pp.input_per_mtok + coalesce(p_cache_write,0) * pp.input_per_mtok * 1.25
          + coalesce(p_cache_read,0) * pp.input_per_mtok * 0.1 + coalesce(p_out,0) * pp.output_per_mtok) / 1000000.0;
    how := case when pp.matched like '(unknown%' then '料金表にないモデル・最高値で計算' else '料金表' end;
  end if;
  usd := coalesce(usd, 0) + ex;
  jpy := greatest(0.01, round(usd * rate, 2));
  insert into requests (agent_id, merchant, amount, reason, status, note, decided_at, source, day)
  values (p_agent, sb_merchant_name(p_provider), jpy,
    format('%s · 入力%s / 出力%s トークン%s', coalesce(nullif(p_model,''),'不明なモデル'),
      coalesce(p_in,0) + coalesce(p_cache_write,0) + coalesce(p_cache_read,0), coalesce(p_out,0),
      case when ex > 0 then ' · ' || coalesce(nullif(p_extra_note, ''), 'tools') end),
    'approved_auto', coalesce(p_note, format('API利用(中継で自動計測・%s)', how)), now(), 'proxy', p_day)
  returning id into rid;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_estimate_usd(p_provider text, p_model text, p_in bigint, p_out bigint)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pp record;
begin
  select * into pp from sb_price_for(p_provider, p_model, p_in);
  return (greatest(coalesce(p_in, 0), 0) * pp.input_per_mtok * 1.25 + greatest(coalesce(p_out, 0), 0) * pp.output_per_mtok) / 1000000.0;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_expire(p_agent uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s proxy_inflight; rid bigint; n int := 0;
begin
  for s in select * from proxy_inflight where agent_id = p_agent and settled_at is null
           and started_at < now() - sb_proxy_expire_after() for update loop
    insert into requests (agent_id, merchant, amount, reason, status, note, decided_at, source, day)
    values (s.agent_id, coalesce(sb_merchant_name(coalesce(s.provider,'')), 'API'), s.reserved_jpy,
      format('%s · 応答が戻らず打ち切り', coalesce(nullif(s.model,''),'不明なモデル')),
      'approved_auto', 'API利用(精算が届かず・予約額で計上)', now(), 'proxy', (s.started_at at time zone sb_agent_tz(s.agent_id))::date)
    returning id into rid;
    update proxy_inflight set settled_at = now(), settled_jpy = s.reserved_jpy, request_id = rid, basis = 'expired' where id = s.id;
    n := n + 1;
  end loop;
  delete from proxy_inflight where agent_id = p_agent and settled_at < now() - interval '1 day';
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_expire_after()
 RETURNS interval
 LANGUAGE sql
 STABLE
AS $function$ select coalesce(nullif(current_setting('saifuban.expire_after', true), ''), '10 minutes')::interval $function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_release(p_slot bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update proxy_inflight set settled_at = now(), settled_jpy = 0, basis = 'released'
  where id = p_slot and settled_at is null
$function$
;

CREATE OR REPLACE FUNCTION public.sb_proxy_settle(p_slot bigint, p_provider text, p_model text, p_in bigint, p_out bigint, p_cache_write bigint, p_cache_read bigint, p_cost_usd numeric, p_basis text DEFAULT 'usage'::text, p_extra_usd numeric DEFAULT 0, p_extra_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s proxy_inflight; c record; d date;
begin
  select * into s from proxy_inflight where id = p_slot for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_slot'); end if;
  d := (s.started_at at time zone sb_agent_tz(s.agent_id))::date;
  if s.settled_at is not null then
    if s.basis in ('expired', 'cancelled') and p_basis = 'usage' then
      select * into c from sb_proxy_charge(s.agent_id, p_provider, p_model, p_in, p_out, p_cache_write, p_cache_read, p_cost_usd, null, d, p_extra_usd, p_extra_note);
      delete from requests where id = s.request_id;
      update proxy_inflight set settled_jpy = c.jpy, request_id = c.rid, basis = 'usage_late' where id = p_slot;
      return jsonb_build_object('ok', true, 'corrected', true, 'jpy', c.jpy, 'was', s.settled_jpy, 'day', d);
    end if;
    return jsonb_build_object('ok', true, 'duplicate', true, 'jpy', s.settled_jpy, 'basis', s.basis);
  end if;
  select * into c from sb_proxy_charge(s.agent_id, p_provider, p_model, p_in, p_out, p_cache_write, p_cache_read, p_cost_usd,
    case when p_basis = 'cancelled' then 'API利用(途中で切断・予約額で計上)' end, d, p_extra_usd, p_extra_note);
  update proxy_inflight set settled_at = now(), settled_jpy = c.jpy, request_id = c.rid, basis = p_basis where id = p_slot;
  return jsonb_build_object('ok', true, 'jpy', c.jpy, 'basis', p_basis, 'day', d);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_public_status(s text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case s when 'approved_auto' then 'approved' when 'approved' then 'approved'
    when 'pending' then 'pending_approval' when 'expired' then 'expired' else 'denied' end;
$function$
;

CREATE OR REPLACE FUNCTION public.sb_push_gone(p_endpoint text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update push_subs set active = false where endpoint = p_endpoint;
$function$
;

CREATE OR REPLACE FUNCTION public.sb_push_targets(p_owner uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('endpoint', endpoint, 'keys', jsonb_build_object('p256dh', p256dh, 'auth', auth))), '[]'::jsonb)
  from push_subs where owner_id = p_owner and active;
$function$
;

CREATE OR REPLACE FUNCTION public.sb_redeem_token(p_token text, p_merchant text, p_amount_jpy numeric, p_consume boolean, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare m text[]; rid bigint; r requests; a agents; exp timestamptz;
begin
  m := regexp_match(coalesce(p_token,''), '^sbt_([0-9]{1,18})_([0-9a-f]{40})$');
  if m is null then return jsonb_build_object('valid', false, 'error', 'malformed_token'); end if;
  rid := m[1]::bigint;
  if sb_token_for(rid) <> p_token then return jsonb_build_object('valid', false, 'error', 'invalid_token'); end if;
  select * into r from requests where id = rid for update;
  if r.id is null then return jsonb_build_object('valid', false, 'error', 'invalid_token'); end if;
  if r.status not in ('approved','approved_auto') then return jsonb_build_object('valid', false, 'error', 'not_approved'); end if;
  exp := coalesce(r.decided_at, r.created_at) + interval '24 hours';
  if now() > exp then return jsonb_build_object('valid', false, 'error', 'expired'); end if;
  if r.redeemed_at is not null then return jsonb_build_object('valid', false, 'error', 'already_used', 'used_at', r.redeemed_at); end if;
  select * into a from agents where id = r.agent_id;
  if a.archived or not a.active or sb_killed(a.owner_id) then return jsonb_build_object('valid', false, 'error', 'agent_stopped'); end if;
  if p_merchant is not null and btrim(p_merchant) <> '' and lower(btrim(p_merchant)) <> lower(r.merchant) then
    return jsonb_build_object('valid', false, 'error', 'merchant_mismatch', 'approved_merchant', r.merchant);
  end if;
  if p_amount_jpy is not null and p_amount_jpy > r.amount + 0.5 then
    return jsonb_build_object('valid', false, 'error', 'amount_exceeds_approval', 'approved_amount_jpy', r.amount);
  end if;
  if p_consume then
    update requests set redeemed_at = now(), redeemed_by = left(coalesce(p_by,''), 200) where id = r.id;
  end if;
  return jsonb_build_object('valid', true, 'consumed', p_consume, 'request_id', r.id, 'merchant', r.merchant,
    'approved_amount_jpy', r.amount, 'expires_at', exp, 'prefs', sb_owner_prefs(a.owner_id));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_relay_secret()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
  select decrypted_secret from vault.decrypted_secrets where name = 'saifuban_relay_secret' limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.sb_request(p_key text, p_merchant text, p_amount integer, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select sb_request_v2(p_key, p_merchant, p_amount, p_reason, null)
$function$
;

CREATE OR REPLACE FUNCTION public.sb_request_v2(p_key text, p_merchant text, p_amount integer, p_reason text, p_recurring text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select sb_request_v3(p_key, p_merchant, p_amount, p_reason, p_recurring, null)
$function$
;

CREATE OR REPLACE FUNCTION public.sb_request_v3(p_key text, p_merchant text, p_amount integer, p_reason text, p_recurring text, p_idem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  a agents; u record; st text; nt text; rid bigint; mer text := btrim(coalesce(p_merchant,''));
  rec text := case when lower(coalesce(p_recurring,'')) in ('week','month','year') then lower(p_recurring) else null end;
  idem text := nullif(left(btrim(coalesce(p_idem,'')), 200), '');
  detected boolean := false; first boolean; annual numeric; ex requests; pb text;
begin
  a := sb_agent_by_key(p_key);
  if a.id is null or a.archived then return jsonb_build_object('error','invalid_agent_key'); end if;
  if mer = '' or char_length(mer) > 200 then return jsonb_build_object('error','merchant_required'); end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('error','amount_must_be_positive'); end if;
  perform 1 from agents where id = a.id for update;
  perform sb_expire();

  if idem is not null then
    select * into ex from requests where agent_id = a.id and idem_key = idem;
  end if;
  if ex.id is null then
    select * into ex from requests
     where agent_id = a.id and status = 'pending' and lower(merchant) = lower(mer) and amount = p_amount
       and coalesce(recurring,'') = coalesce(rec, case when sb_looks_recurring(mer || ' ' || coalesce(p_reason,'')) then 'unknown' end, '')
       and created_at > now() - interval '24 hours'
     order by created_at desc limit 1;
  end if;
  if ex.id is not null then
    select * into u from sb_usage(a.id);
    return jsonb_build_object('request_id', ex.id, 'status', sb_public_status(ex.status), 'reason', ex.note,
      'amount_jpy', ex.amount, 'merchant', ex.merchant, 'recurring', coalesce(ex.recurring, 'none'),
      'duplicate', true, 'duplicate_of', ex.id,
      'remaining_today_jpy', floor(greatest(0, a.daily - u.spent - u.reserved)));
  end if;

  -- 大量送信の制限(同じAIから1分に30件まで)
  if (select count(*) from requests where agent_id = a.id and created_at > now() - interval '1 minute') >= 30 then
    return jsonb_build_object('error','rate_limited','retry_after_seconds',60,'message','Too many payment requests. Max 30 per minute per agent.');
  end if;
  select * into u from sb_usage(a.id);
  if rec is null and sb_looks_recurring(mer || ' ' || coalesce(p_reason,'')) then rec := 'unknown'; detected := true; end if;
  annual := case rec when 'week' then p_amount * 52 when 'month' then p_amount * 12 when 'year' then p_amount else null end;
  -- 前に「支払い済み(承認済み)」になったことがあるか(自動承認・持ち主の承認どちらでも)
  first := not exists (select 1 from requests where agent_id = a.id and lower(merchant) = lower(mer) and status in ('approved','approved_auto'));
  pb := sb_period_block(a, p_amount, false);

  if sb_killed(a.owner_id) then st := 'denied'; nt := '緊急停止中';
  elsif not a.active then st := 'denied'; nt := 'このAIは停止中';
  elsif not sb_merchant_ok(a.merchants, mer) then st := 'denied'; nt := '許可していない支払先';
  elsif p_amount > a.per_tx then st := 'denied'; nt := format('1回の上限(%s円)を超過', a.per_tx);
  elsif u.spent + u.reserved + p_amount > a.daily then st := 'denied'; nt := format('1日の予算(%s円)を超過', a.daily);
  elsif pb is not null then st := 'denied'; nt := pb;
  elsif rec is not null then st := 'pending';
    nt := case when annual is not null then format('定期購入のため確認が必要(年%s円)', to_char(annual, 'FM999,999,999,990'))
               else '定期購入の可能性があるため確認が必要' end;
  elsif p_amount <= a.auto_approve and a.auto_known_only and first then st := 'pending'; nt := '初めての支払先のため確認が必要';
  elsif p_amount <= a.auto_approve then st := 'approved_auto'; nt := format('自動承認(%s円以下)', a.auto_approve);
  else st := 'pending'; nt := case when a.auto_approve > 0 then format('聞かずに払っていい額(%s円)を超過', a.auto_approve) else '人間の承認が必要' end;
  end if;

  insert into requests (agent_id, merchant, amount, reason, status, note, decided_at, recurring, recurring_detected, first_merchant, idem_key)
  values (a.id, mer, p_amount, left(coalesce(p_reason,''), 500), st, nt, case when st = 'pending' then null else now() end, rec, detected, first, idem)
  returning id into rid;
  select * into u from sb_usage(a.id);

  return jsonb_build_object('request_id', rid, 'status', sb_public_status(st), 'reason', nt,
    'amount_jpy', p_amount, 'merchant', mer,
    'recurring', coalesce(rec, 'none'), 'recurring_detected', detected,
    'annual_cost_jpy', annual, 'first_time_merchant', first, 'duplicate', false,
    'remaining_today_jpy', floor(greatest(0, a.daily - u.spent - u.reserved)));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_requests_fill_day()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.day is null then new.day := (coalesce(new.created_at, now()) at time zone sb_agent_tz(new.agent_id))::date; end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_rotate_key(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare k text := 'sbk_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  update agents set key_hash = encode(extensions.digest(k, 'sha256'), 'hex'), key_hint = left(k, 10) || '…' where id = p_id;
  if not found then return jsonb_build_object('error','agent_not_found'); end if;
  return jsonb_build_object('ok', true, 'agent_key', k);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_set_kill(p_kill boolean)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update settings set kill = p_kill, updated_at = now() where id = 1;
  select jsonb_build_object('ok', true, 'kill', p_kill);
$function$
;

CREATE OR REPLACE FUNCTION public.sb_set_notify(p_topic text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_topic is not null and p_topic !~ '^[A-Za-z0-9_-]{16,64}$' then return jsonb_build_object('error','bad_topic'); end if;
  update settings set ntfy_topic = p_topic, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_set_provider_key(p_provider text, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
declare old uuid; sid uuid; k text := btrim(coalesce(p_key,''));
begin
  if sb_merchant_name(p_provider) is null then return jsonb_build_object('error','bad_provider'); end if;
  select secret_id into old from provider_keys where provider = p_provider;
  if k = '' then
    if old is not null then
      perform vault.update_secret(old, 'unset');
      update provider_keys set enabled = false, hint = '', updated_at = now() where provider = p_provider;
    end if;
    return jsonb_build_object('ok', true, 'removed', true);
  end if;
  if char_length(k) < 20 or k ~ '\s' then return jsonb_build_object('error','bad_key'); end if;
  if old is not null then
    perform vault.update_secret(old, k);
    update provider_keys set hint = left(k, 7) || '…' || right(k, 4), enabled = true, updated_at = now() where provider = p_provider;
  else
    sid := vault.create_secret(k, 'saifuban_' || p_provider || '_' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint);
    insert into provider_keys (provider, secret_id, hint) values (p_provider, sid, left(k, 7) || '…' || right(k, 4));
  end if;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_status(p_key text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a agents; r requests;
begin
  a := sb_agent_by_key(p_key);
  if a.id is null then return jsonb_build_object('error','invalid_agent_key'); end if;
  perform sb_expire();
  select * into r from requests where id = p_id and agent_id = a.id;
  if r.id is null then return jsonb_build_object('error','request_not_found'); end if;
  return jsonb_build_object('request_id', r.id, 'status', sb_public_status(r.status), 'reason', r.note,
    'amount_jpy', r.amount, 'merchant', r.merchant, 'decided_at', r.decided_at,
    'recurring', coalesce(r.recurring, 'none'));
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_sync_tick()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j sync_jobs; resp record; note text := ''; res numeric; n int;
begin
  for j in select * from sync_jobs where req_id is not null loop
    select status_code, content into resp from net._http_response where id = j.req_id;
    if resp.status_code = 200 then
      if j.kind = 'prices' then n := sb_prices_apply(resp.content::jsonb); note := note || format('prices %s; ', n);
        update sync_jobs set req_id = null, last_ok_at = now(), last_note = format('%s models', n) where kind = j.kind;
      elsif j.kind = 'fx' then res := sb_fx_apply(resp.content::jsonb); note := note || format('fx %s; ', res);
        update sync_jobs set req_id = null, last_ok_at = case when res is not null then now() else last_ok_at end, last_note = coalesce(res::text, 'rejected') where kind = j.kind;
      end if;
    elsif resp.status_code is not null or j.requested_at < now() - interval '1 hour' then
      update sync_jobs set req_id = null, last_note = format('failed (%s)', coalesce(resp.status_code::text, 'no response')) where kind = j.kind;
    end if;
  end loop;
  insert into sync_jobs (kind) values ('prices'), ('fx') on conflict do nothing;
  update sync_jobs set req_id = net.http_get(url := 'https://openrouter.ai/api/v1/models', timeout_milliseconds := 30000), requested_at = now()
    where kind = 'prices' and req_id is null and (last_ok_at is null or last_ok_at < now() - interval '20 hours');
  update sync_jobs set req_id = net.http_get(url := 'https://open.er-api.com/v6/latest/USD', timeout_milliseconds := 30000), requested_at = now()
    where kind = 'fx' and req_id is null and (last_ok_at is null or last_ok_at < now() - interval '20 hours');
  return note;
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_today(p_agent uuid)
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select (now() at time zone sb_agent_tz(p_agent))::date $function$
;

CREATE OR REPLACE FUNCTION public.sb_token_for(p_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select 'sbt_' || p_id || '_' || left(encode(extensions.hmac(p_id::text, (select decrypted_secret from vault.decrypted_secrets where name='payment_token_secret'), 'sha256'),'hex'), 40)
$function$
;

CREATE OR REPLACE FUNCTION public.sb_update_agent(p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update agents set name = btrim(p_name), per_tx = greatest(0, p_per_tx), daily = greatest(0, p_daily),
    auto_approve = greatest(0, p_auto), merchants = array(select btrim(m) from unnest(p_merchants) m where btrim(m) <> ''),
    active = p_active
  where id = p_id;
  if not found then return jsonb_build_object('error','agent_not_found'); end if;
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_usage(p_agent uuid)
 RETURNS TABLE(spent numeric, reserved numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    coalesce(sum(amount) filter (where status in ('approved_auto','approved')), 0)::numeric,
    coalesce(sum(amount) filter (where status = 'pending'), 0)::numeric + sb_inflight_jpy(p_agent)
  from requests
  where agent_id = p_agent and day = sb_today(p_agent);
$function$
;

CREATE OR REPLACE FUNCTION public.sb_usage_since(p_agent uuid, p_from date)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(amount) filter (where status in ('approved_auto','approved','pending')), 0)::numeric + sb_inflight_jpy(p_agent)
  from requests where agent_id = p_agent and day >= p_from
$function$
;

CREATE OR REPLACE FUNCTION public.sb_used(p_agent uuid)
 RETURNS TABLE(spent bigint, reserved bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    coalesce(sum(amount) filter (where status in ('approved_auto','approved')), 0),
    coalesce(sum(amount) filter (where status = 'pending'), 0)
  from requests
  where agent_id = p_agent and day = sb_today(p_agent);
$function$
;

CREATE OR REPLACE FUNCTION public.sb_vapid_get()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
declare s settings; v text;
begin
  select * into s from settings where id = 1;
  if s.vapid_secret_id is null then return null; end if;
  select decrypted_secret into v from vault.decrypted_secrets where id = s.vapid_secret_id;
  return jsonb_build_object('keys', v::jsonb, 'public', s.vapid_public);
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_vapid_init(p_keys text, p_public text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
declare sid uuid;
begin
  perform 1 from settings where id = 1 for update;
  if (select vapid_secret_id from settings where id = 1) is null then
    sid := vault.create_secret(p_keys, 'saifuban_vapid');
    update settings set vapid_secret_id = sid, vapid_public = p_public where id = 1;
  end if;
  return sb_vapid_get();
end $function$
;

CREATE OR REPLACE FUNCTION public.sb_vapid_public()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select vapid_public from settings where id = 1;
$function$
;

CREATE OR REPLACE FUNCTION public.sb_week_start()
 RETURNS date
 LANGUAGE sql
 STABLE
AS $function$
  select date_trunc('week', (now() at time zone 'Asia/Tokyo'))::date $function$
;

CREATE OR REPLACE FUNCTION public.sb_week_start(p_agent uuid)
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select date_trunc('week', now() at time zone sb_agent_tz(p_agent))::date $function$
;

-- triggers
CREATE TRIGGER requests_fill_day BEFORE INSERT ON public.requests FOR EACH ROW EXECUTE FUNCTION sb_requests_fill_day();
CREATE TRIGGER agents_oauth_revoke AFTER UPDATE ON public.agents FOR EACH ROW EXECUTE FUNCTION oauth_revoke_on_rotate();

-- function privileges
revoke all on function public.app_archive_agent(p_owner_key text, p_id uuid) from public, anon, authenticated; grant execute on function public.app_archive_agent(p_owner_key text, p_id uuid) to service_role;
revoke all on function public.app_create_agent(p_owner_key text, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[]) from public, anon, authenticated; grant execute on function public.app_create_agent(p_owner_key text, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[]) to service_role;
revoke all on function public.app_dashboard(p_owner_key text) from public, anon, authenticated; grant execute on function public.app_dashboard(p_owner_key text) to service_role;
revoke all on function public.app_decide(p_owner_key text, p_id bigint, p_approve boolean) from public, anon, authenticated; grant execute on function public.app_decide(p_owner_key text, p_id bigint, p_approve boolean) to service_role;
revoke all on function public.app_oauth_decide(p_owner_key text, p_req text, p_agent uuid, p_new_name text, p_daily integer, p_auto integer, p_approve boolean) from public, anon, authenticated; grant execute on function public.app_oauth_decide(p_owner_key text, p_req text, p_agent uuid, p_new_name text, p_daily integer, p_auto integer, p_approve boolean) to service_role;
revoke all on function public.app_oauth_info(p_owner_key text, p_req text) from public, anon, authenticated; grant execute on function public.app_oauth_info(p_owner_key text, p_req text) to service_role;
revoke all on function public.app_owner(p_key text) from public, anon, authenticated; grant execute on function public.app_owner(p_key text) to service_role;
revoke all on function public.app_owner_prefs(p_owner_key text) from public, anon, authenticated; grant execute on function public.app_owner_prefs(p_owner_key text) to service_role;
revoke all on function public.app_push_subscribe(p_owner_key text, p_endpoint text, p_p256dh text, p_auth text) from public, anon, authenticated; grant execute on function public.app_push_subscribe(p_owner_key text, p_endpoint text, p_p256dh text, p_auth text) to service_role;
revoke all on function public.app_push_unsubscribe(p_owner_key text, p_endpoint text) from public, anon, authenticated; grant execute on function public.app_push_unsubscribe(p_owner_key text, p_endpoint text) to service_role;
revoke all on function public.app_rotate_key(p_owner_key text, p_id uuid) from public, anon, authenticated; grant execute on function public.app_rotate_key(p_owner_key text, p_id uuid) to service_role;
revoke all on function public.app_set_currency(p_owner_key text, p_currency text) from public, anon, authenticated; grant execute on function public.app_set_currency(p_owner_key text, p_currency text) to service_role;
revoke all on function public.app_set_kill(p_owner_key text, p_kill boolean) from public, anon, authenticated; grant execute on function public.app_set_kill(p_owner_key text, p_kill boolean) to service_role;
revoke all on function public.app_set_lang(p_owner_key text, p_lang text) from public, anon, authenticated; grant execute on function public.app_set_lang(p_owner_key text, p_lang text) to service_role;
revoke all on function public.app_set_ntfy(p_owner_key text, p_topic text) from public, anon, authenticated; grant execute on function public.app_set_ntfy(p_owner_key text, p_topic text) to service_role;
revoke all on function public.app_set_provider_key(p_owner_key text, p_provider text, p_key text) from public, anon, authenticated; grant execute on function public.app_set_provider_key(p_owner_key text, p_provider text, p_key text) to service_role;
revoke all on function public.app_set_tz(p_owner_key text, p_tz text, p_auto boolean) from public, anon, authenticated; grant execute on function public.app_set_tz(p_owner_key text, p_tz text, p_auto boolean) to service_role;
revoke all on function public.app_signup() from public, anon, authenticated; grant execute on function public.app_signup() to service_role;
revoke all on function public.app_track(p_event text, p_src text, p_lang text) from public, anon, authenticated; grant execute on function public.app_track(p_event text, p_src text, p_lang text) to service_role;
revoke all on function public.app_update_agent(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean) from public, anon, authenticated; grant execute on function public.app_update_agent(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean) to service_role;
revoke all on function public.app_update_agent_v2(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer) from public, anon, authenticated; grant execute on function public.app_update_agent_v2(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer) to service_role;
revoke all on function public.app_update_agent_v3(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer, p_known_only boolean) from public, anon, authenticated; grant execute on function public.app_update_agent_v3(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer, p_known_only boolean) to service_role;
revoke all on function public.app_update_agent_v4(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer, p_known_only boolean, p_max_concurrent integer) from public, anon, authenticated; grant execute on function public.app_update_agent_v4(p_owner_key text, p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean, p_weekly integer, p_monthly integer, p_known_only boolean, p_max_concurrent integer) to service_role;
revoke all on function public.oauth_authorize_start(p_client text, p_redirect text, p_challenge text, p_method text, p_state text, p_scope text) from public, anon, authenticated; grant execute on function public.oauth_authorize_start(p_client text, p_redirect text, p_challenge text, p_method text, p_state text, p_scope text) to service_role;
revoke all on function public.oauth_issue(p_agent uuid, p_client text) from public, anon, authenticated; grant execute on function public.oauth_issue(p_agent uuid, p_client text) to service_role;
revoke all on function public.oauth_redirect_ok(p_allowed text[], p_uri text) from public, anon, authenticated; grant execute on function public.oauth_redirect_ok(p_allowed text[], p_uri text) to anon; grant execute on function public.oauth_redirect_ok(p_allowed text[], p_uri text) to authenticated; grant execute on function public.oauth_redirect_ok(p_allowed text[], p_uri text) to service_role;
revoke all on function public.oauth_register(p_redirect_uris text[], p_name text) from public, anon, authenticated; grant execute on function public.oauth_register(p_redirect_uris text[], p_name text) to service_role;
revoke all on function public.oauth_revoke_agent(p_agent uuid) from public, anon, authenticated; grant execute on function public.oauth_revoke_agent(p_agent uuid) to service_role;
revoke all on function public.oauth_revoke_on_rotate() from public, anon, authenticated; grant execute on function public.oauth_revoke_on_rotate() to anon; grant execute on function public.oauth_revoke_on_rotate() to authenticated; grant execute on function public.oauth_revoke_on_rotate() to service_role;
revoke all on function public.oauth_token_code(p_client text, p_code text, p_verifier text, p_redirect text) from public, anon, authenticated; grant execute on function public.oauth_token_code(p_client text, p_code text, p_verifier text, p_redirect text) to service_role;
revoke all on function public.oauth_token_refresh(p_client text, p_refresh text) from public, anon, authenticated; grant execute on function public.oauth_token_refresh(p_client text, p_refresh text) to service_role;
revoke all on function public.oauth_token_valid(p_token text) from public, anon, authenticated; grant execute on function public.oauth_token_valid(p_token text) to service_role;
revoke all on function public.sb_agent_by_key(p_key text) from public, anon, authenticated; grant execute on function public.sb_agent_by_key(p_key text) to service_role;
revoke all on function public.sb_agent_tz(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_agent_tz(p_agent uuid) to anon; grant execute on function public.sb_agent_tz(p_agent uuid) to authenticated; grant execute on function public.sb_agent_tz(p_agent uuid) to service_role;
revoke all on function public.sb_budget(p_key text) from public, anon, authenticated; grant execute on function public.sb_budget(p_key text) to service_role;
revoke all on function public.sb_create_agent(p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[]) from public, anon, authenticated; grant execute on function public.sb_create_agent(p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[]) to service_role;
revoke all on function public.sb_dashboard() from public, anon, authenticated; grant execute on function public.sb_dashboard() to service_role;
revoke all on function public.sb_decide(p_id bigint, p_approve boolean) from public, anon, authenticated; grant execute on function public.sb_decide(p_id bigint, p_approve boolean) to service_role;
revoke all on function public.sb_decide_token(p_id bigint, p_token text, p_approve boolean) from public, anon, authenticated; grant execute on function public.sb_decide_token(p_id bigint, p_token text, p_approve boolean) to service_role;
revoke all on function public.sb_delete_agent(p_id uuid) from public, anon, authenticated; grant execute on function public.sb_delete_agent(p_id uuid) to service_role;
revoke all on function public.sb_expire() from public, anon, authenticated; grant execute on function public.sb_expire() to service_role;
revoke all on function public.sb_fx_apply(p_body jsonb) from public, anon, authenticated; grant execute on function public.sb_fx_apply(p_body jsonb) to service_role;
revoke all on function public.sb_h(t text) from public, anon, authenticated; grant execute on function public.sb_h(t text) to anon; grant execute on function public.sb_h(t text) to authenticated; grant execute on function public.sb_h(t text) to service_role;
revoke all on function public.sb_history(p_key text, p_merchant text, p_days integer, p_limit integer) from public, anon, authenticated; grant execute on function public.sb_history(p_key text, p_merchant text, p_days integer, p_limit integer) to service_role;
revoke all on function public.sb_inflight_jpy(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_inflight_jpy(p_agent uuid) to service_role;
revoke all on function public.sb_issue_token(p_key text, p_id bigint) from public, anon, authenticated; grant execute on function public.sb_issue_token(p_key text, p_id bigint) to service_role;
revoke all on function public.sb_key_prefs(p_key text) from public, anon, authenticated; grant execute on function public.sb_key_prefs(p_key text) to service_role;
revoke all on function public.sb_killed(p_owner uuid) from public, anon, authenticated; grant execute on function public.sb_killed(p_owner uuid) to service_role;
revoke all on function public.sb_looks_recurring(p_text text) from public, anon, authenticated; grant execute on function public.sb_looks_recurring(p_text text) to service_role;
revoke all on function public.sb_max_output(p_provider text, p_model text) from public, anon, authenticated; grant execute on function public.sb_max_output(p_provider text, p_model text) to service_role;
revoke all on function public.sb_merchant_name(p_provider text) from public, anon, authenticated; grant execute on function public.sb_merchant_name(p_provider text) to service_role;
revoke all on function public.sb_merchant_ok(p_list text[], p_mer text) from public, anon, authenticated; grant execute on function public.sb_merchant_ok(p_list text[], p_mer text) to service_role;
revoke all on function public.sb_money_for(p_owner uuid, p_jpy numeric) from public, anon, authenticated; grant execute on function public.sb_money_for(p_owner uuid, p_jpy numeric) to service_role;
revoke all on function public.sb_month_start(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_month_start(p_agent uuid) to anon; grant execute on function public.sb_month_start(p_agent uuid) to authenticated; grant execute on function public.sb_month_start(p_agent uuid) to service_role;
revoke all on function public.sb_month_start() from public, anon, authenticated; grant execute on function public.sb_month_start() to anon; grant execute on function public.sb_month_start() to authenticated; grant execute on function public.sb_month_start() to service_role;
revoke all on function public.sb_notify_prepare(p_id bigint) from public, anon, authenticated; grant execute on function public.sb_notify_prepare(p_id bigint) to service_role;
revoke all on function public.sb_owner_lang(p_owner uuid) from public, anon, authenticated; grant execute on function public.sb_owner_lang(p_owner uuid) to service_role;
revoke all on function public.sb_owner_prefs(p_owner uuid) from public, anon, authenticated; grant execute on function public.sb_owner_prefs(p_owner uuid) to service_role;
revoke all on function public.sb_owner_topic(p_owner uuid) from public, anon, authenticated; grant execute on function public.sb_owner_topic(p_owner uuid) to service_role;
revoke all on function public.sb_period_block(a agents, p_add numeric, p_en boolean) from public, anon, authenticated; grant execute on function public.sb_period_block(a agents, p_add numeric, p_en boolean) to service_role;
revoke all on function public.sb_price_for(p_provider text, p_model text, p_prompt_tokens bigint, OUT input_per_mtok numeric, OUT output_per_mtok numeric, OUT matched text) from public, anon, authenticated; grant execute on function public.sb_price_for(p_provider text, p_model text, p_prompt_tokens bigint, OUT input_per_mtok numeric, OUT output_per_mtok numeric, OUT matched text) to service_role;
revoke all on function public.sb_prices_apply(p_body jsonb) from public, anon, authenticated; grant execute on function public.sb_prices_apply(p_body jsonb) to service_role;
revoke all on function public.sb_proxy_begin(p_key text, p_provider text) from public, anon, authenticated; grant execute on function public.sb_proxy_begin(p_key text, p_provider text) to service_role;
revoke all on function public.sb_proxy_begin_v3(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint) from public, anon, authenticated; grant execute on function public.sb_proxy_begin_v3(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint) to service_role;
revoke all on function public.sb_proxy_begin_v4(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint, p_extra_usd numeric, p_choices integer) from public, anon, authenticated; grant execute on function public.sb_proxy_begin_v4(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint, p_extra_usd numeric, p_choices integer) to service_role;
revoke all on function public.sb_proxy_begin_v5(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint, p_extra_usd numeric, p_choices integer, p_min_out bigint) from public, anon, authenticated; grant execute on function public.sb_proxy_begin_v5(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint, p_extra_usd numeric, p_choices integer, p_min_out bigint) to service_role;
revoke all on function public.sb_proxy_charge(p_agent uuid, p_provider text, p_model text, p_in bigint, p_out bigint, p_cache_write bigint, p_cache_read bigint, p_cost_usd numeric, p_note text, p_day date, p_extra_usd numeric, p_extra_note text, OUT rid bigint, OUT jpy numeric) from public, anon, authenticated; grant execute on function public.sb_proxy_charge(p_agent uuid, p_provider text, p_model text, p_in bigint, p_out bigint, p_cache_write bigint, p_cache_read bigint, p_cost_usd numeric, p_note text, p_day date, p_extra_usd numeric, p_extra_note text, OUT rid bigint, OUT jpy numeric) to service_role;
revoke all on function public.sb_proxy_estimate_usd(p_provider text, p_model text, p_in bigint, p_out bigint) from public, anon, authenticated; grant execute on function public.sb_proxy_estimate_usd(p_provider text, p_model text, p_in bigint, p_out bigint) to service_role;
revoke all on function public.sb_proxy_expire(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_proxy_expire(p_agent uuid) to service_role;
revoke all on function public.sb_proxy_expire_after() from public, anon, authenticated; grant execute on function public.sb_proxy_expire_after() to anon; grant execute on function public.sb_proxy_expire_after() to authenticated; grant execute on function public.sb_proxy_expire_after() to service_role;
revoke all on function public.sb_proxy_release(p_slot bigint) from public, anon, authenticated; grant execute on function public.sb_proxy_release(p_slot bigint) to service_role;
revoke all on function public.sb_proxy_settle(p_slot bigint, p_provider text, p_model text, p_in bigint, p_out bigint, p_cache_write bigint, p_cache_read bigint, p_cost_usd numeric, p_basis text, p_extra_usd numeric, p_extra_note text) from public, anon, authenticated; grant execute on function public.sb_proxy_settle(p_slot bigint, p_provider text, p_model text, p_in bigint, p_out bigint, p_cache_write bigint, p_cache_read bigint, p_cost_usd numeric, p_basis text, p_extra_usd numeric, p_extra_note text) to service_role;
revoke all on function public.sb_public_status(s text) from public, anon, authenticated; grant execute on function public.sb_public_status(s text) to service_role;
revoke all on function public.sb_push_gone(p_endpoint text) from public, anon, authenticated; grant execute on function public.sb_push_gone(p_endpoint text) to service_role;
revoke all on function public.sb_push_targets(p_owner uuid) from public, anon, authenticated; grant execute on function public.sb_push_targets(p_owner uuid) to service_role;
revoke all on function public.sb_redeem_token(p_token text, p_merchant text, p_amount_jpy numeric, p_consume boolean, p_by text) from public, anon, authenticated; grant execute on function public.sb_redeem_token(p_token text, p_merchant text, p_amount_jpy numeric, p_consume boolean, p_by text) to service_role;
revoke all on function public.sb_relay_secret() from public, anon, authenticated; grant execute on function public.sb_relay_secret() to service_role;
revoke all on function public.sb_request(p_key text, p_merchant text, p_amount integer, p_reason text) from public, anon, authenticated; grant execute on function public.sb_request(p_key text, p_merchant text, p_amount integer, p_reason text) to service_role;
revoke all on function public.sb_request_v2(p_key text, p_merchant text, p_amount integer, p_reason text, p_recurring text) from public, anon, authenticated; grant execute on function public.sb_request_v2(p_key text, p_merchant text, p_amount integer, p_reason text, p_recurring text) to service_role;
revoke all on function public.sb_request_v3(p_key text, p_merchant text, p_amount integer, p_reason text, p_recurring text, p_idem text) from public, anon, authenticated; grant execute on function public.sb_request_v3(p_key text, p_merchant text, p_amount integer, p_reason text, p_recurring text, p_idem text) to service_role;
revoke all on function public.sb_requests_fill_day() from public, anon, authenticated; grant execute on function public.sb_requests_fill_day() to anon; grant execute on function public.sb_requests_fill_day() to authenticated; grant execute on function public.sb_requests_fill_day() to service_role;
revoke all on function public.sb_rotate_key(p_id uuid) from public, anon, authenticated; grant execute on function public.sb_rotate_key(p_id uuid) to service_role;
revoke all on function public.sb_set_kill(p_kill boolean) from public, anon, authenticated; grant execute on function public.sb_set_kill(p_kill boolean) to service_role;
revoke all on function public.sb_set_notify(p_topic text) from public, anon, authenticated; grant execute on function public.sb_set_notify(p_topic text) to service_role;
revoke all on function public.sb_set_provider_key(p_provider text, p_key text) from public, anon, authenticated; grant execute on function public.sb_set_provider_key(p_provider text, p_key text) to service_role;
revoke all on function public.sb_status(p_key text, p_id bigint) from public, anon, authenticated; grant execute on function public.sb_status(p_key text, p_id bigint) to service_role;
revoke all on function public.sb_sync_tick() from public, anon, authenticated; grant execute on function public.sb_sync_tick() to service_role;
revoke all on function public.sb_today(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_today(p_agent uuid) to anon; grant execute on function public.sb_today(p_agent uuid) to authenticated; grant execute on function public.sb_today(p_agent uuid) to service_role;
revoke all on function public.sb_token_for(p_id bigint) from public, anon, authenticated; grant execute on function public.sb_token_for(p_id bigint) to service_role;
revoke all on function public.sb_update_agent(p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean) from public, anon, authenticated; grant execute on function public.sb_update_agent(p_id uuid, p_name text, p_per_tx integer, p_daily integer, p_auto integer, p_merchants text[], p_active boolean) to service_role;
revoke all on function public.sb_usage(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_usage(p_agent uuid) to service_role;
revoke all on function public.sb_usage_since(p_agent uuid, p_from date) from public, anon, authenticated; grant execute on function public.sb_usage_since(p_agent uuid, p_from date) to service_role;
revoke all on function public.sb_used(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_used(p_agent uuid) to service_role;
revoke all on function public.sb_vapid_get() from public, anon, authenticated; grant execute on function public.sb_vapid_get() to service_role;
revoke all on function public.sb_vapid_init(p_keys text, p_public text) from public, anon, authenticated; grant execute on function public.sb_vapid_init(p_keys text, p_public text) to service_role;
revoke all on function public.sb_vapid_public() from public, anon, authenticated; grant execute on function public.sb_vapid_public() to service_role;
revoke all on function public.sb_week_start() from public, anon, authenticated; grant execute on function public.sb_week_start() to anon; grant execute on function public.sb_week_start() to authenticated; grant execute on function public.sb_week_start() to service_role;
revoke all on function public.sb_week_start(p_agent uuid) from public, anon, authenticated; grant execute on function public.sb_week_start(p_agent uuid) to anon; grant execute on function public.sb_week_start(p_agent uuid) to authenticated; grant execute on function public.sb_week_start(p_agent uuid) to service_role;

-- settings row and starting prices (the hourly sync adds the rest from OpenRouter)
insert into public.settings (id) values (1) on conflict do nothing;
update public.settings set app_url = 'https://ut181749ut.github.io/saifuban/' where id = 1;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, '', 15, null, 75, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-opus-4-0', 15, null, 75, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-opus-4-2025', 15, null, 75, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-sonnet', 3, null, 15, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-3-7-sonnet', 3, null, 15, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-3-5-sonnet', 3, null, 15, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-haiku', 1, null, 5, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-3-5-haiku', 0.8, null, 4, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-3-haiku', 0.25, null, 1.25, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'openai', null, '', 15, null, 60, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'openai', null, 'o4-mini', 1.1, null, 4.4, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'openai', null, 'text-embedding-3-small', 0.02, null, 0, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'openai', null, 'text-embedding-3-large', 0.13, null, 0, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'google', null, '', 10, null, 40, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'google', null, 'gemini-2.0-flash', 0.1, null, 0.4, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'google', null, 'gemini-2.0-flash-lite', 0.075, null, 0.3, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'google', null, 'text-embedding', 0.15, null, 0, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'google', null, 'gemini-embedding', 0.15, null, 0, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'openrouter', null, '', 15, null, 75, null, null) on conflict do nothing;
insert into public.prices (source, provider, max_output, model_prefix, input_per_mtok, long_threshold, output_per_mtok, long_input_per_mtok, long_output_per_mtok) values ('manual', 'anthropic', null, 'claude-opus', 15, null, 75, null, null) on conflict do nothing;

-- secrets: one for payment tokens, one shared with the Cloudflare relay
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'payment_token_secret')
  where not exists (select 1 from vault.secrets where name = 'payment_token_secret');
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'saifuban_relay_secret')
  where not exists (select 1 from vault.secrets where name = 'saifuban_relay_secret');

-- prices and exchange rate: fetched hourly (refreshed once a day)
select cron.schedule('saifuban-sync', '7 * * * *', 'select public.sb_sync_tick()');
select public.sb_sync_tick();
