-- 予算切れのとき、持ち主のスマホに「今日だけ予算を足す」ボタン付きの通知を出す
alter table public.agents add column if not exists boost_jpy numeric not null default 0;
alter table public.agents add column if not exists boost_day date;
alter table public.agents add column if not exists alert_day date;
alter table public.agents add column if not exists boost_token_hash text;
alter table public.agents add column if not exists boost_token_day date;
alter table public.settings add column if not exists functions_url text;

-- 今日の使用額から「今日だけ足した分」を引く(1日の予算の判定がすべてこれを使う)
CREATE OR REPLACE FUNCTION public.sb_usage(p_agent uuid)
 RETURNS TABLE(spent numeric, reserved numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    coalesce(sum(amount) filter (where status in ('approved_auto','approved')), 0)::numeric
      - coalesce((select boost_jpy from agents where id = p_agent and boost_day = sb_today(p_agent)), 0),
    coalesce(sum(amount) filter (where status = 'pending'), 0)::numeric + sb_inflight_jpy(p_agent)
  from requests
  where agent_id = p_agent and day = sb_today(p_agent);
$function$;

-- 予算切れの通知を出す(1つのAIにつき1日1回だけ)。通知は saifuban 関数が送る
CREATE OR REPLACE FUNCTION public.sb_budget_alert_fire(p_agent uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare d date := sb_today(p_agent); u text;
begin
  update agents set alert_day = d where id = p_agent and alert_day is distinct from d;
  if not found then return; end if;
  select functions_url into u from settings where id = 1;
  if u is null then return; end if;
  perform net.http_post(u || '/saifuban/budget-alert', jsonb_build_object('agent', p_agent), '{}'::jsonb,
    jsonb_build_object('x-saifuban-relay', sb_relay_secret(), 'content-type', 'application/json'), 10000);
end $function$;

-- 通知の中身を用意する。ボタン用の使い捨ての合言葉もここで作る(AIには渡らない)
CREATE OR REPLACE FUNCTION public.sb_budget_alert_prepare(p_agent uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a agents; t text := encode(extensions.gen_random_bytes(24), 'hex'); pr jsonb; topic text; targets jsonb; amt numeric;
begin
  select * into a from agents where id = p_agent;
  if a.id is null or a.owner_id is null then return jsonb_build_object('skip', true); end if;
  topic := sb_owner_topic(a.owner_id);
  targets := sb_push_targets(a.owner_id);
  if topic is null and jsonb_array_length(targets) = 0 then return jsonb_build_object('skip', true); end if;
  update agents set boost_token_hash = encode(extensions.digest(t, 'sha256'), 'hex'), boost_token_day = sb_today(a.id) where id = a.id;
  pr := sb_owner_prefs(a.owner_id);
  amt := sb_boost_amount(a.owner_id);
  return jsonb_build_object('topic', topic, 'push', targets, 'token', t, 'agent_id', a.id, 'agent', a.name,
    'daily', a.daily, 'boost', amt, 'app_url', (select app_url from settings where id = 1),
    'lang', pr->>'lang', 'currency', pr->>'currency', 'rate', (pr->>'rate')::numeric);
end $function$;

-- 足す額: 円なら500円、ドルなら$3
CREATE OR REPLACE FUNCTION public.sb_boost_amount(p_owner uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when coalesce((select currency from owners where id = p_owner), 'JPY') = 'USD'
              then ceil(3 * (select usd_jpy from settings where id = 1)) else 500 end
$function$;

-- 通知のボタンから: 今日だけ予算を足す(合言葉は1回だけ・今日だけ有効)
CREATE OR REPLACE FUNCTION public.sb_boost(p_agent uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a agents; d date; amt numeric; pr jsonb;
begin
  select * into a from agents where id = p_agent for update;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  d := sb_today(a.id);
  if a.boost_token_hash is null or a.boost_token_day is distinct from d
     or a.boost_token_hash <> encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex') then
    return jsonb_build_object('ok', false, 'error', 'used_or_expired');
  end if;
  amt := sb_boost_amount(a.owner_id);
  update agents set boost_jpy = case when boost_day = d then boost_jpy else 0 end + amt, boost_day = d,
    boost_token_hash = null, alert_day = null where id = a.id;
  pr := sb_owner_prefs(a.owner_id);
  return jsonb_build_object('ok', true, 'amount', amt, 'agent', a.name, 'owner_id', a.owner_id,
    'lang', pr->>'lang', 'currency', pr->>'currency', 'rate', (pr->>'rate')::numeric);
end $function$;

revoke all on function public.sb_budget_alert_fire(uuid) from public, anon, authenticated;
revoke all on function public.sb_budget_alert_prepare(uuid) from public, anon, authenticated;
revoke all on function public.sb_boost_amount(uuid) from public, anon, authenticated;
revoke all on function public.sb_boost(uuid, text) from public, anon, authenticated;
grant execute on function public.sb_budget_alert_prepare(uuid) to service_role;
grant execute on function public.sb_boost(uuid, text) to service_role;

-- 自分で動かす場合は、自分のプロジェクトのアドレスを入れる(入れないと通知だけ出ない):
-- update public.settings set functions_url = 'https://<your-project-ref>.supabase.co/functions/v1' where id = 1;

-- sb_proxy_begin_v5 の「1日の予算切れ」で通知を出す
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.sb_proxy_begin_v5'::regproc);
  if position('sb_budget_alert_fire' in d) > 0 then return; end if;
  d := replace(d,
    $x$      return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'budget', 'period', 'daily'$x$,
    $x$      perform sb_budget_alert_fire(a.id);  -- 持ち主のスマホに「今日だけ予算を足す」ボタン付きの通知(1日1回)
      return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'budget', 'period', 'daily'$x$);
  if position('sb_budget_alert_fire' in d) = 0 then raise exception 'hook point not found'; end if;
  execute d;
end $do$;
