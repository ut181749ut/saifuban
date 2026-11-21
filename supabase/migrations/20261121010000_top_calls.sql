-- 画面に「この7日で高かった呼び出し」上位5件と7日の合計を出す。毎朝のレポート用の列も用意しておく
alter table public.owners add column if not exists report_off boolean not null default false;
alter table public.owners add column if not exists report_day date;
alter table public.owners add column if not exists report_token_hash text;

do $do$
declare d text;
begin
  d := pg_get_functiondef('public.app_dashboard(text)'::regprocedure);
  if position('''top''' in d) > 0 then return; end if;
  d := replace(d, $x$    'requests', coalesce($x$,
    $x$    -- この7日で一番高かったAPIの呼び出し(どこでお金がかかっているかを見せる)
    'top', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'agent', t.name, 'amount', t.amount, 'reason', t.reason, 'created_at', t.created_at) order by t.amount desc)
      from (select r.id, a.name, r.amount, r.reason, r.created_at from requests r join agents a on a.id = r.agent_id
            where a.owner_id = o.id and r.source = 'proxy' and r.status in ('approved_auto', 'approved') and r.created_at > now() - interval '7 days'
            order by r.amount desc limit 5) t), '[]'::jsonb),
    'week_api', (select coalesce(sum(r.amount), 0) from requests r join agents a on a.id = r.agent_id
            where a.owner_id = o.id and r.source = 'proxy' and r.status in ('approved_auto', 'approved') and r.created_at > now() - interval '7 days'),
    'report_off', o.report_off,
    'requests', coalesce($x$);
  if position('''top''' in d) = 0 then raise exception 'hook point not found'; end if;
  execute d;
end $do$;
