-- 持ち主ごとの時間帯のテスト(すべて最後に取り消すので、本番のデータは残らない)
-- ロサンゼルスの持ち主(上限 ¥100)と、日本の持ち主(上限 ¥100)で、同じ瞬間の「今日」と区切りを比べる。
do $$
declare
  o_la uuid; o_jp uuid; a_la uuid; a_jp uuid; k_la text := 'sbk_test_' || md5(random()::text); k_jp text := 'sbk_test_' || md5(random()::text);
  ok_la text := 'sbo_' || left(md5(random()::text) || md5(random()::text), 48); sec uuid; r jsonb; log jsonb := '[]'::jsonb; s bigint;
  la_today date := (now() at time zone 'America/Los_Angeles')::date; jp_today date := (now() at time zone 'Asia/Tokyo')::date;
  la_2359 timestamptz := ((la_today::timestamp - interval '1 minute') at time zone 'America/Los_Angeles');
begin
  perform set_config('saifuban.expire_after', '100 years', true);
  insert into owners (key_hash, key_hint) values (sb_h(ok_la), 'sbo_test…') returning id into o_la;
  insert into owners (key_hash, key_hint) values (sb_h('sbo_' || md5(random()::text)), 'sbo_test…') returning id into o_jp;
  insert into agents (name, key_hash, key_hint, per_tx, daily, auto_approve, owner_id) values ('tz LA', sb_h(k_la), 'sbk…', 100, 100, 100, o_la) returning id into a_la;
  insert into agents (name, key_hash, key_hint, per_tx, daily, auto_approve, owner_id) values ('tz JP', sb_h(k_jp), 'sbk…', 100, 100, 100, o_jp) returning id into a_jp;
  sec := vault.create_secret('dummy', 'sbtest_' || md5(random()::text));
  insert into owner_provider_keys (owner_id, provider, secret_id, enabled) values (o_la, 'anthropic', sec, true);
  sec := vault.create_secret('dummy', 'sbtest_' || md5(random()::text));
  insert into owner_provider_keys (owner_id, provider, secret_id, enabled) values (o_jp, 'anthropic', sec, true);

  -- 時間帯の設定: 画面を開いたときの自動設定は最初の1回だけ。手動ならいつでも変えられる。存在しない時間帯は拒否
  log := log || jsonb_build_object('step', 'auto set LA (first time)', 'result', app_set_tz(ok_la, 'America/Los_Angeles', true));
  log := log || jsonb_build_object('step', 'auto set Europe/Paris (already set, ignored)', 'result', app_set_tz(ok_la, 'Europe/Paris', true));
  log := log || jsonb_build_object('step', 'bad time zone', 'result', app_set_tz(ok_la, 'Mars/Olympus', false));
  log := log || jsonb_build_object('step', 'now', 'utc', now(), 'la_today', la_today, 'jp_today', jp_today,
    'la_resets', sb_budget(k_la)->'budget_resets_at', 'jp_resets', sb_budget(k_jp)->'budget_resets_at');

  -- 同じ瞬間に1回ずつ使う → 日付はそれぞれの時間帯の「今日」
  r := sb_proxy_begin_v3(k_la, 'anthropic', 'claude-sonnet-4-5', 1000, 19000); s := (r->>'slot')::bigint;
  r := sb_proxy_settle(s, 'anthropic', 'claude-sonnet-4-5', 1000, 4000, 0, 0, null);
  log := log || jsonb_build_object('step', 'LA call settled', 'day', r->'day', 'la_today_spent', (select spent from sb_usage(a_la)));
  r := sb_proxy_begin_v3(k_jp, 'anthropic', 'claude-sonnet-4-5', 1000, 19000); s := (r->>'slot')::bigint;
  r := sb_proxy_settle(s, 'anthropic', 'claude-sonnet-4-5', 1000, 4000, 0, 0, null);
  log := log || jsonb_build_object('step', 'JP call settled', 'day', r->'day', 'jp_today_spent', (select spent from sb_usage(a_jp)));
  -- 支払いの申請(MCP)も、持ち主の時間帯の日付で記録される
  r := sb_request_v3(k_la, 'Example Store', 30, 'test', null, null);
  log := log || jsonb_build_object('step', 'LA payment request', 'status', r->'status',
    'day', (select day from requests where id = (r->>'request_id')::bigint), 'la_today_spent', (select spent from sb_usage(a_la)));

  -- ロサンゼルスの 23:59 に始まり、0時を過ぎて精算 → ロサンゼルスの前日に計上
  insert into proxy_inflight (agent_id, reserved_jpy, provider, model, started_at) values (a_la, 45, 'anthropic', 'claude-sonnet-4-5', la_2359) returning id into s;
  r := sb_proxy_settle(s, 'anthropic', 'claude-sonnet-4-5', 1000, 2000, 0, 0, null);
  log := log || jsonb_build_object('step', 'LA call from 23:59 settled after midnight', 'day', r->'day', 'expected_day', la_today - 1,
    'la_today_spent', (select spent from sb_usage(a_la)));

  log := log || jsonb_build_object('step', 'final', 'la_today_spent', (select spent from sb_usage(a_la)), 'jp_today_spent', (select spent from sb_usage(a_jp)),
    'expected', jsonb_build_object('la_today', 9.77 + 30, 'jp_today', 9.77));
  raise exception 'RESULT %', log;
end $$;
