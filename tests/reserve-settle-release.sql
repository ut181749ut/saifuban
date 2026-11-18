-- 予約→精算→解放のテスト(すべて最後に取り消すので、本番のデータは残らない)
-- 1日の上限 ¥100 のAIで、従量の呼び出しを2つ同時に始める。
-- 1つ目の精算を遅らせ、同じ精算を再送し、そのあと取り消しを送る。
-- 各段階の判断・予約中の額・計上済みの額を記録し、最後に例外で全部ロールバックして結果を返す。
-- 場面2: 1つ目の精算が10分以上届かない(処理が強制終了した)場合も同じ順で確かめる。
-- 場面3: 取り消しが精算より先に届く場合。
do $$
declare
  o uuid; a uuid; sec uuid; key text;
  r jsonb; log jsonb := '[]'::jsonb; sa bigint; sb bigint; scene text;
  -- claude-sonnet: 入力$3 / 出力$15 (100万トークンあたり)、1ドル155円
  -- 予約: 入力1000 + 出力上限19000 → $0.288 → ¥45
  -- 実際: A 入力1000/出力2000 → ¥5.12、B 入力1000/出力4000 → ¥9.77
begin
  for scene in select unnest(array['1_delayed_retry_cancel', '2_callback_lost_past_10min', '3_cancel_arrives_first']) loop
    key := 'sbk_test_' || md5(random()::text);
    insert into owners (key_hash, key_hint) values (sb_h('sbo_' || md5(random()::text)), 'sbo_test…') returning id into o;
    insert into agents (name, key_hash, key_hint, per_tx, daily, auto_approve, owner_id)
      values ('reserve-settle test', sb_h(key), 'sbk_test…', 100, 100, 100, o) returning id into a;
    sec := vault.create_secret('dummy-provider-key', 'sbtest_' || md5(random()::text));
    insert into owner_provider_keys (owner_id, provider, secret_id, enabled) values (o, 'anthropic', sec, true);

    -- 2つ同時に開始
    r := sb_proxy_begin_v3(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000); sa := (r->>'slot')::bigint;
    log := log || jsonb_build_object('scene', scene, 'step', 'begin A', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
      'reserved_for_call', r->'reserved_jpy', 'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));
    r := sb_proxy_begin_v3(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000); sb := (r->>'slot')::bigint;
    log := log || jsonb_build_object('scene', scene, 'step', 'begin B', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
      'reserved_for_call', r->'reserved_jpy', 'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));
    -- 3つ目は上限を超えるので止まるはず(¥90予約中 + ¥45 > ¥100)
    r := sb_proxy_begin_v3(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
    log := log || jsonb_build_object('scene', scene, 'step', 'begin C (check)', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
      'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));
    if not (r ? 'error') then perform sb_proxy_release((r->>'slot')::bigint); end if;

    -- Bが先に終わる(Aの精算は遅れている)
    r := sb_proxy_settle(sb, 'anthropic', 'claude-sonnet-4-5', 1000, 4000, 0, 0, null);
    log := log || jsonb_build_object('scene', scene, 'step', 'settle B', 'result', r, 'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));

    if scene = '2_callback_lost_past_10min' then
      -- Aの精算が10分以上届かない → 次の呼び出しの入口で、予約額のまま計上される
      update proxy_inflight set started_at = now() - interval '11 minutes' where id = sa;
      r := sb_proxy_begin_v3(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
      log := log || jsonb_build_object('scene', scene, 'step', 'next call after 11 min (A expires)', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
        'a_row', (select jsonb_build_object('basis', basis, 'settled_jpy', settled_jpy) from proxy_inflight where id = sa),
        'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));
      if not (r ? 'error') then perform sb_proxy_release((r->>'slot')::bigint); end if;
    end if;

    if scene = '3_cancel_arrives_first' then
      -- 取り消し(接続切れ)が先に届く → いったん予約額で計上し、予約は空く
      r := sb_proxy_settle(sa, 'anthropic', 'claude-sonnet-4-5 (estimate: stream cut)', 0, 0, 0, 0, 0.288, 'cancelled');
      log := log || jsonb_build_object('scene', scene, 'step', 'cancel A (before its settle)', 'result', r, 'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));
    end if;

    -- 遅れてAの精算が届く
    r := sb_proxy_settle(sa, 'anthropic', 'claude-sonnet-4-5', 1000, 2000, 0, 0, null);
    log := log || jsonb_build_object('scene', scene, 'step', 'settle A (delayed)', 'result', r, 'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));
    -- 同じ精算の再送
    r := sb_proxy_settle(sa, 'anthropic', 'claude-sonnet-4-5', 1000, 2000, 0, 0, null);
    log := log || jsonb_build_object('scene', scene, 'step', 'settle A (retry)', 'result', r, 'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));
    -- そのあと取り消し(接続が切れたときの「予約額で計上」と、何も使わなかったときの「解放」の両方)
    r := sb_proxy_settle(sa, 'anthropic', 'claude-sonnet-4-5 (estimate: stream cut)', 0, 0, 0, 0, 0.288, 'cancelled');
    perform sb_proxy_release(sa);
    log := log || jsonb_build_object('scene', scene, 'step', 'cancel A', 'result', r, 'reserved_total', sb_inflight_jpy(a), 'settled_total', (select spent from sb_usage(a)));

    log := log || jsonb_build_object('scene', scene, 'step', 'final',
      'settled_total', (select spent from sb_usage(a)), 'reserved_total', sb_inflight_jpy(a),
      'charge_rows', (select jsonb_agg(jsonb_build_object('amount', amount, 'reason', reason, 'note', note) order by id) from requests where agent_id = a),
      'expected_total', 5.12 + 9.77);
  end loop;
  raise exception 'RESULT %', log;
end $$;
