-- 日付の境目のテスト(すべて最後に取り消すので、本番のデータは残らない)
-- 1日の区切りは日本時間(Asia/Tokyo)の0時。上限 ¥100 のAIで、前日23:59に始まった呼び出しが日をまたぐ場合を確かめる。
-- 時計は動かせないので、23:59の開始は「その時刻に begin_v3 が作る予約」をそのまま入れて再現する
-- (前日は ¥50 使用済み、¥45 予約 → 50+45 ≤ 100 なので、23:59 の時点では通る呼び出し)。
-- 場面1: 0:01 に精算が届く。場面2: 精算が届かない(10分たって打ち切り)。
do $$
declare
  o uuid; a uuid; sec uuid; key text; r jsonb; log jsonb := '[]'::jsonb; sa bigint; sb bigint; scene text;
  today date := (now() at time zone 'Asia/Tokyo')::date; yday date := today - 1;
  t2359 timestamptz := ((today::timestamp - interval '1 minute') at time zone 'Asia/Tokyo');
begin
  for scene in select unnest(array['1_starts_2359_settles_after_midnight', '2_starts_2359_callback_never_arrives']) loop
    -- 場面1では「まだ0:01」なので打ち切りにしない(10分の打ち切りをこのテストの中だけ止める)
    perform set_config('saifuban.expire_after', case when scene like '1_%' then '100 years' else '10 minutes' end, true);
    key := 'sbk_test_' || md5(random()::text);
    insert into owners (key_hash, key_hint) values (sb_h('sbo_' || md5(random()::text)), 'sbo_test…') returning id into o;
    insert into agents (name, key_hash, key_hint, per_tx, daily, auto_approve, owner_id)
      values ('day-boundary test', sb_h(key), 'sbk_test…', 100, 100, 100, o) returning id into a;
    sec := vault.create_secret('dummy-provider-key', 'sbtest_' || md5(random()::text));
    insert into owner_provider_keys (owner_id, provider, secret_id, enabled) values (o, 'anthropic', sec, true);

    -- 前日: ¥50 使用済み。23:59 に呼び出しAが ¥45 を予約
    insert into requests (agent_id, merchant, amount, reason, status, note, decided_at, source, day, created_at)
      values (a, sb_merchant_name('anthropic'), 50, 'earlier call', 'approved_auto', 'test', t2359, 'proxy', yday, t2359);
    insert into proxy_inflight (agent_id, reserved_jpy, provider, model, started_at)
      values (a, 45, 'anthropic', 'claude-sonnet-4-5', t2359) returning id into sa;
    log := log || jsonb_build_object('scene', scene, 'step', '23:59 A reserved ¥45 (yesterday: ¥50 spent)', 'timezone', 'Asia/Tokyo',
      'yesterday_settled', (select sum(amount) from requests where agent_id = a and day = yday),
      'today_settled', (select spent from sb_usage(a)), 'reserved_total', sb_inflight_jpy(a));

    -- 0時を過ぎて、今日の最初の呼び出しB
    r := sb_proxy_begin_v3(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000); sb := (r->>'slot')::bigint;
    log := log || jsonb_build_object('scene', scene, 'step', 'after midnight: begin B', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
      'a_row', (select jsonb_build_object('basis', basis, 'settled_jpy', settled_jpy) from proxy_inflight where id = sa),
      'yesterday_settled', (select sum(amount) from requests where agent_id = a and day = yday),
      'today_settled', (select spent from sb_usage(a)), 'reserved_total', sb_inflight_jpy(a));
    r := sb_proxy_begin_v3(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
    log := log || jsonb_build_object('scene', scene, 'step', 'after midnight: begin C (check)', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
      'today_settled', (select spent from sb_usage(a)), 'reserved_total', sb_inflight_jpy(a));
    if not (r ? 'error') then perform sb_proxy_release((r->>'slot')::bigint); end if;

    -- 0:01 にAの精算が届く(場面2では打ち切り済みなので、実際の額に直る)
    r := sb_proxy_settle(sa, 'anthropic', 'claude-sonnet-4-5', 1000, 2000, 0, 0, null);
    log := log || jsonb_build_object('scene', scene, 'step', '00:01 settle A', 'result', r,
      'yesterday_settled', (select sum(amount) from requests where agent_id = a and day = yday),
      'today_settled', (select spent from sb_usage(a)), 'reserved_total', sb_inflight_jpy(a));
    r := sb_proxy_settle(sb, 'anthropic', 'claude-sonnet-4-5', 1000, 4000, 0, 0, null);
    log := log || jsonb_build_object('scene', scene, 'step', 'settle B', 'result', r,
      'yesterday_settled', (select sum(amount) from requests where agent_id = a and day = yday),
      'today_settled', (select spent from sb_usage(a)), 'reserved_total', sb_inflight_jpy(a));
    log := log || jsonb_build_object('scene', scene, 'step', 'final',
      'yesterday_settled', (select sum(amount) from requests where agent_id = a and day = yday),
      'today_settled', (select spent from sb_usage(a)), 'reserved_total', sb_inflight_jpy(a),
      'expected', jsonb_build_object('yesterday', 50 + 5.12, 'today', 9.77));
  end loop;
  raise exception 'RESULT %', log;
end $$;
