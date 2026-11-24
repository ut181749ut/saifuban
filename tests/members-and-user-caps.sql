-- 参加者キー(勉強会向け)と利用者ごとの1日の上限(ボット向け)のテスト。最後に例外で全部ロールバックする
-- AIの1日の予算 ¥1,000、1人あたり ¥100。1回の予約は ¥45(claude-sonnet 入力1000 + 出力上限19000)
do $$
declare
  o uuid; a uuid; sec uuid; ok text := 'sbo_' || encode(extensions.gen_random_bytes(24), 'hex'); key text;
  r jsonb; log jsonb := '[]'::jsonb; ka text; kb text; s1 bigint; s2 bigint;
  step text;
begin
  insert into owners (key_hash, key_hint) values (sb_h(ok), 'sbo_test…') returning id into o;
  key := 'sbk_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into agents (name, key_hash, key_hint, per_tx, daily, auto_approve, owner_id, max_concurrent)
    values ('勉強会テスト', sb_h(key), 'sbk_test…', 1000, 1000, 1000, o, 20) returning id into a;
  sec := vault.create_secret('dummy-provider-key', 'sbtest_' || md5(random()::text));
  insert into owner_provider_keys (owner_id, provider, secret_id, enabled) values (o, 'anthropic', sec, true);

  r := app_set_agent_limits(ok, a, 100, null);
  log := log || jsonb_build_object('step', 'per_user_daily=100', 'result', r);
  r := app_members_create(ok, a, array['田中', '佐藤', '田中', '  ']);
  log := log || jsonb_build_object('step', 'create members (dup + blank ignored)', 'labels', (select jsonb_agg(x->'label') from jsonb_array_elements(r->'created') x), 'total', r->'total');
  ka := (select x->>'key' from jsonb_array_elements(r->'created') x where x->>'label' = '田中');
  kb := (select x->>'key' from jsonb_array_elements(r->'created') x where x->>'label' = '佐藤');

  -- 田中: 45 → 90 → 3回目は 135 > 100 で止まる
  for step in select unnest(array['田中 call 1', '田中 call 2', '田中 call 3 (over 100)']) loop
    r := sb_proxy_begin_v6(ka, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
    log := log || jsonb_build_object('step', step, 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
      'user_remaining', r->'user_remaining_jpy', 'user_today', sb_user_today(a, '田中'));
    if s1 is null then s1 := (r->>'slot')::bigint; end if;
  end loop;
  -- 佐藤は別枠なので通る
  r := sb_proxy_begin_v6(kb, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
  log := log || jsonb_build_object('step', '佐藤 call 1', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end, 'end_user', r->'end_user');

  -- 田中の1回目が実際は ¥5.12 で終わる → 今日の額は 5.12 + 45 になり、もう1回通る
  r := sb_proxy_settle(s1, 'anthropic', 'claude-sonnet-4-5', 1000, 2000, 0, 0, null);
  r := sb_proxy_begin_v6(ka, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
  log := log || jsonb_build_object('step', '田中 after call 1 settled at actual', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end,
    'user_today', sb_user_today(a, '田中'));

  -- ボット: 本来のキー + ヘッダーのユーザーID。同じ上限がかかる。IDなしなら利用者ごとの上限はかからない
  for step in select unnest(array['discord:1 call 1', 'discord:1 call 2', 'discord:1 call 3 (over 100)']) loop
    r := sb_proxy_begin_v6(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000, 0, 1, 0, 'discord:1');
    log := log || jsonb_build_object('step', step, 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end);
  end loop;
  r := sb_proxy_begin_v6(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
  log := log || jsonb_build_object('step', 'no user id', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end, 'end_user', r->'end_user');

  log := log || jsonb_build_object('step', 'list', 'result', app_members_list(ok, a));

  -- 田中のキーを止める → 使えない。佐藤はまだ使える
  r := app_members_revoke(ok, a, (select id from agent_members where agent_id = a and label = '田中'));
  r := sb_proxy_begin_v6(ka, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
  log := log || jsonb_build_object('step', '田中 after revoke', 'decision', coalesce(r->>'error', 'allowed'));
  r := sb_proxy_begin_v6(kb, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
  log := log || jsonb_build_object('step', '佐藤 after 田中 revoked', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end);

  -- 期限切れ → 全員止まる
  perform app_set_agent_limits(ok, a, 100, now() - interval '1 minute');
  r := sb_proxy_begin_v6(kb, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
  log := log || jsonb_build_object('step', '佐藤 after expiry', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end);
  r := sb_proxy_begin_v6(key, 'anthropic', 'claude-sonnet-4-5', 1000, 19000);
  log := log || jsonb_build_object('step', 'main key after expiry', 'decision', case when r ? 'error' then 'blocked: ' || (r->>'reason') else 'allowed' end);

  raise exception 'RESULT %', log;
end $$;
