-- 勉強会・授業向け: 1つのAIに参加者ごとのキー(メンバーキー)をまとめて発行し、期限が来たら全部止まる
-- ボット向け: 呼び出しごとのユーザー(x-saifuban-user ヘッダーなど)に1日の上限をかける
-- どちらも「AIの中の利用者(end_user)」ごとに数える。メンバーキーなら名前、ヘッダーならそのID

alter table agents add column if not exists per_user_daily integer;   -- 1人あたりの1日の上限(円)。null = 上限なし
alter table agents add column if not exists expires_at timestamptz;   -- この時刻を過ぎたらAPIの呼び出しを止める。null = 期限なし
alter table proxy_inflight add column if not exists end_user text;
create index if not exists proxy_inflight_end_user_idx on proxy_inflight (agent_id, end_user, started_at) where end_user is not null;

create table if not exists agent_members (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references agents(id) on delete cascade,
  label text not null,
  key_hash text not null unique,
  key_hint text not null,
  revoked boolean not null default false,
  created_at timestamptz not null default now(),
  unique (agent_id, label)
);
alter table agent_members enable row level security;  -- 直接は読めない(関数からだけ)

-- メンバーキーでも、そのAIとして通す
CREATE OR REPLACE FUNCTION public.sb_agent_by_key(p_key text)
 RETURNS agents LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
  select * from agents where key_hash = sb_h(p_key)
  union all
  select a.* from oauth_tokens t join agents a on a.id = t.agent_id
   where p_key like 'sbk_oa_%' and t.access_hash = sb_h(p_key) and not t.revoked and t.access_expires > now()
  union all
  select a.* from agent_members m join agents a on a.id = m.agent_id
   where p_key like 'sbk_m_%' and m.key_hash = sb_h(p_key) and not m.revoked
  limit 1
$function$;

-- 期限切れのAIは、本物のキーを渡す前に止める
CREATE OR REPLACE FUNCTION public.sb_proxy_begin(p_key text, p_provider text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions', 'vault'
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
  if a.expires_at is not null and a.expires_at <= now() then return jsonb_build_object('error','blocked','lang', case when en then 'en' else 'ja' end,
    'reason', case when en then 'This key has expired' else 'このキーは期限が切れました' end); end if;
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
end $function$;

-- 利用者ごとの今日の額(精算済みは実額、まだなら予約額)
CREATE OR REPLACE FUNCTION public.sb_user_today(p_agent uuid, p_user text, p_except bigint DEFAULT 0)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select coalesce(sum(coalesce(settled_jpy, reserved_jpy)), 0)::numeric from proxy_inflight
   where agent_id = p_agent and end_user = p_user and id <> coalesce(p_except, 0)
     and (started_at at time zone sb_agent_tz(p_agent))::date = sb_today(p_agent)
$function$;

-- v5 に「利用者ごとの1日の上限」を足したもの。v5 がAIの行をロックしたまま(同じトランザクション)なので、同時の呼び出しでも抜けない
CREATE OR REPLACE FUNCTION public.sb_proxy_begin_v6(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint,
  p_extra_usd numeric DEFAULT 0, p_choices integer DEFAULT 1, p_min_out bigint DEFAULT 0, p_user text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions', 'vault'
AS $function$
declare g jsonb; a agents; eu text; used numeric; est numeric; en boolean; reset_at timestamptz;
begin
  g := sb_proxy_begin_v5(p_key, p_provider, p_model, p_in_est, p_out_max, p_extra_usd, p_choices, p_min_out);
  if g ? 'error' then return g; end if;
  a := sb_agent_by_key(p_key);
  -- メンバーキーならその名前、そうでなければヘッダーなどで渡されたID
  select label into eu from agent_members where key_hash = sb_h(p_key) and p_key like 'sbk_m_%';
  eu := coalesce(eu, nullif(left(btrim(coalesce(p_user, '')), 100), ''));
  if eu is null then return g; end if;
  update proxy_inflight set end_user = eu where id = (g->>'slot')::bigint;
  if a.per_user_daily is null then return g; end if;
  est := (g->>'reserved_jpy')::numeric;
  used := sb_user_today(a.id, eu, (g->>'slot')::bigint);
  if used + est > a.per_user_daily then
    delete from proxy_inflight where id = (g->>'slot')::bigint;  -- まだ誰にも見えていない予約なので消すだけ
    en := g->>'lang' = 'en';
    reset_at := ((sb_today(a.id) + 1)::timestamp at time zone sb_agent_tz(a.id));
    return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'budget', 'period', 'daily', 'reset_at', reset_at, 'scope', 'user',
      'reason', case when en then format('Daily limit for this user reached: this call could cost up to %s and %s is left for "%s". Resets at %s',
                       sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(a.per_user_daily - used))), eu, to_char(reset_at at time zone sb_agent_tz(a.id), 'YYYY-MM-DD HH24:MI'))
                     else format('「%s」の1日の上限に達しました(この呼び出しは最大%s、残り%s)。%sにリセットされます',
                       eu, sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(a.per_user_daily - used))), to_char(reset_at at time zone sb_agent_tz(a.id), 'MM/DD HH24:MI')) end);
  end if;
  return g || jsonb_build_object('end_user', eu, 'user_remaining_jpy', floor(a.per_user_daily - used - est));
end $function$;

-- 参加者のキーをまとめて作る(キーはこのときだけ返す)。1つのAIにつき300人まで
CREATE OR REPLACE FUNCTION public.app_members_create(p_owner_key text, p_agent uuid, p_labels text[])
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
declare o owners; lb text; k text; out jsonb := '[]'::jsonb; n int;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if not exists (select 1 from agents where id = p_agent and owner_id = o.id and not archived) then return jsonb_build_object('error','not_found'); end if;
  select count(*) into n from agent_members where agent_id = p_agent;
  for lb in select distinct on (l) l from (select left(btrim(x), 60) l, ord from unnest(coalesce(p_labels, '{}')) with ordinality t(x, ord)) s where l <> '' order by l, ord loop
    if n >= 300 then exit; end if;
    if exists (select 1 from agent_members where agent_id = p_agent and label = lb) then continue; end if;
    k := 'sbk_m_' || encode(extensions.gen_random_bytes(24), 'hex');
    insert into agent_members (agent_id, label, key_hash, key_hint) values (p_agent, lb, sb_h(k), left(k, 12) || '…');
    out := out || jsonb_build_object('label', lb, 'key', k);
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'created', out, 'total', n);
end $function$;

-- 参加者・利用者ごとの使った額(今日と合計)。メンバーキーとヘッダーで来たIDの両方
CREATE OR REPLACE FUNCTION public.app_members_list(p_owner_key text, p_agent uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare o owners; a agents;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  select * into a from agents where id = p_agent and owner_id = o.id and not archived;
  if a.id is null then return jsonb_build_object('error','not_found'); end if;
  return jsonb_build_object('ok', true, 'per_user_daily', a.per_user_daily, 'expires_at', a.expires_at,
    'members', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'label', m.label, 'hint', m.key_hint, 'revoked', m.revoked,
        'today', sb_user_today(a.id, m.label), 'total', (select coalesce(sum(coalesce(settled_jpy, reserved_jpy)), 0) from proxy_inflight where agent_id = a.id and end_user = m.label))
        order by m.created_at) from agent_members m where m.agent_id = a.id), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(jsonb_build_object('user', x.end_user, 'today', x.today, 'calls', x.calls) order by x.today desc)
      from (select end_user, sum(coalesce(settled_jpy, reserved_jpy)) today, count(*) calls from proxy_inflight
            where agent_id = a.id and end_user is not null and end_user not in (select label from agent_members where agent_id = a.id)
              and (started_at at time zone sb_agent_tz(a.id))::date = sb_today(a.id)
            group by end_user order by 2 desc limit 50) x), '[]'::jsonb));
end $function$;

-- 参加者のキーを止める(p_member が null なら全員)
CREATE OR REPLACE FUNCTION public.app_members_revoke(p_owner_key text, p_agent uuid, p_member uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare o owners; n int;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  if not exists (select 1 from agents where id = p_agent and owner_id = o.id) then return jsonb_build_object('error','not_found'); end if;
  update agent_members set revoked = true where agent_id = p_agent and (p_member is null or id = p_member) and not revoked;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'revoked', n);
end $function$;

-- 1人あたりの1日の上限と、期限を決める(空 = なし)
CREATE OR REPLACE FUNCTION public.app_set_agent_limits(p_owner_key text, p_id uuid, p_per_user_daily integer, p_expires_at timestamptz)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare o owners;
begin
  o := app_owner(p_owner_key);
  if o.id is null then return jsonb_build_object('error','invalid_owner_key'); end if;
  update agents set per_user_daily = case when coalesce(p_per_user_daily, 0) > 0 then least(p_per_user_daily, 100000000) end,
                    expires_at = p_expires_at
   where id = p_id and owner_id = o.id and not archived;
  if not found then return jsonb_build_object('error','not_found'); end if;
  return jsonb_build_object('ok', true);
end $function$;

-- 管理画面にも出す
CREATE OR REPLACE FUNCTION public.app_dashboard(p_owner_key text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
        'per_user_daily', a.per_user_daily, 'expires_at', a.expires_at,
        'members', (select count(*) from agent_members m where m.agent_id = a.id and not m.revoked),
        'spent', u.spent, 'reserved', u.reserved) order by a.created_at)
      from agents a cross join lateral sb_usage(a.id) u where a.owner_id = o.id and not a.archived), '[]'::jsonb),
    -- この7日で一番高かったAPIの呼び出し(どこでお金がかかっているかを見せる)
    'top', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'agent', t.name, 'amount', t.amount, 'reason', t.reason, 'created_at', t.created_at) order by t.amount desc)
      from (select r.id, a.name, r.amount, r.reason, r.created_at from requests r join agents a on a.id = r.agent_id
            where a.owner_id = o.id and r.source = 'proxy' and r.status in ('approved_auto', 'approved') and r.created_at > now() - interval '7 days'
            order by r.amount desc limit 5) t), '[]'::jsonb),
    'week_api', (select coalesce(sum(r.amount), 0) from requests r join agents a on a.id = r.agent_id
            where a.owner_id = o.id and r.source = 'proxy' and r.status in ('approved_auto', 'approved') and r.created_at > now() - interval '7 days'),
    'report_off', o.report_off,
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'agent_id', r.agent_id, 'merchant', r.merchant,
        'amount', r.amount, 'reason', r.reason, 'status', r.status, 'note', r.note, 'created_at', r.created_at, 'source', r.source)
        order by r.created_at desc)
      from (select r.* from requests r join agents a on a.id = r.agent_id where a.owner_id = o.id and not a.archived
            order by r.created_at desc limit 150) r), '[]'::jsonb));
end $function$;

revoke all on function public.sb_proxy_begin_v6(text, text, text, bigint, bigint, numeric, integer, bigint, text) from public, anon, authenticated;
revoke all on function public.sb_user_today(uuid, text, bigint) from public, anon, authenticated;
revoke all on function public.app_members_create(text, uuid, text[]) from public, anon, authenticated;
revoke all on function public.app_members_list(text, uuid) from public, anon, authenticated;
revoke all on function public.app_members_revoke(text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.app_set_agent_limits(text, uuid, integer, timestamptz) from public, anon, authenticated;
