-- やり直しが来ても前の呼び出しが数秒で止まらない(固まった接続など)ときは、前の分をいったん予約額で計上して枠を空ける。
-- 前の呼び出しがあとで終われば、実際の額(または届いた分からの見積もり)に直す
CREATE OR REPLACE FUNCTION public.sb_proxy_hold(p_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s proxy_inflight; rid bigint; n int := 0;
begin
  for s in select * from proxy_inflight where id = any(p_ids) and settled_at is null for update loop
    insert into requests (agent_id, merchant, amount, reason, status, note, decided_at, source, day)
    values (s.agent_id, coalesce(sb_merchant_name(coalesce(s.provider,'')), 'API'), s.reserved_jpy,
      format('%s · やり直しが来たので予約額で仮計上', coalesce(nullif(s.model,''),'不明なモデル')),
      'approved_auto', 'API利用(仮計上・終わったら実際の額に直す)', now(), 'proxy', (s.started_at at time zone sb_agent_tz(s.agent_id))::date)
    returning id into rid;
    update proxy_inflight set settled_at = now(), settled_jpy = s.reserved_jpy, request_id = rid, basis = 'held' where id = s.id;
    n := n + 1;
  end loop;
  return n;
end $function$;
revoke all on function public.sb_proxy_hold(bigint[]) from public, anon, authenticated;
grant execute on function public.sb_proxy_hold(bigint[]) to service_role;

-- 仮計上(held)の呼び出しは、あとから届いた精算(実際の額・途中で切れた分の見積もり)で直す
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.sb_proxy_settle'::regproc);
  if position('''held''' in d) > 0 then return; end if;
  d := replace(d, $x$if s.basis in ('expired', 'cancelled') and p_basis = 'usage' then$x$,
                  $x$if (s.basis in ('expired', 'cancelled') and p_basis = 'usage') or s.basis = 'held' then$x$);
  d := replace(d, $x$p_cost_usd, null, d, p_extra_usd, p_extra_note);$x$,
                  $x$p_cost_usd, case when p_basis = 'cancelled' then 'API利用(途中で切断・届いた分から見積もり)' end, d, p_extra_usd, p_extra_note);$x$);
  if position('''held''' in d) = 0 then raise exception 'hook point not found'; end if;
  execute d;
end $do$;
