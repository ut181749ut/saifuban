-- やり直し(同じ呼び出しの再送)が来たら、前の呼び出しが残っていても二重に予約しない:
-- 前のものに「置き換えられた」印を付け、前の流れはそれを見て上流を切り、届いた分で精算する
alter table public.proxy_inflight add column if not exists retry_key text;
alter table public.proxy_inflight add column if not exists superseded_at timestamptz;
alter table public.proxy_inflight add column if not exists watch_token text;
create index if not exists proxy_inflight_retry_idx on public.proxy_inflight (agent_id, retry_key) where settled_at is null;

-- 同じ印でまだ終わっていない前の呼び出しに「置き換えられた」と付け、その予約の番号を返す
CREATE OR REPLACE FUNCTION public.sb_proxy_supersede(p_key text, p_slot bigint, p_retry_key text, p_is_retry boolean)
 RETURNS bigint[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a agents; ids bigint[];
begin
  a := sb_agent_by_key(p_key);
  if a.id is null or p_retry_key is null then return '{}'; end if;
  update proxy_inflight set retry_key = p_retry_key where id = p_slot and agent_id = a.id;
  if not p_is_retry then return '{}'; end if;
  with x as (
    update proxy_inflight set superseded_at = now()
    where agent_id = a.id and retry_key = p_retry_key and settled_at is null and superseded_at is null and id <> coalesce(p_slot, 0)
    returning id)
  select coalesce(array_agg(id), '{}') into ids from x;
  return ids;
end $function$;

-- 前の呼び出しがすべて精算されたか(待つ側が見る)
CREATE OR REPLACE FUNCTION public.sb_proxy_slots_open(p_ids bigint[])
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int from proxy_inflight where id = any(p_ids) and settled_at is null
$function$;

-- 流している側(Worker)が数秒ごとに見る: 置き換えられたか。合言葉はその呼び出しにだけ渡したもの
CREATE OR REPLACE FUNCTION public.sb_slot_superseded(p_slot bigint, p_token text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select superseded_at is not null from proxy_inflight where id = p_slot and watch_token = p_token and watch_token is not null), false)
$function$;

revoke all on function public.sb_proxy_supersede(text, bigint, text, boolean) from public, anon, authenticated;
revoke all on function public.sb_proxy_slots_open(bigint[]) from public, anon, authenticated;
grant execute on function public.sb_proxy_supersede(text, bigint, text, boolean) to service_role;
grant execute on function public.sb_proxy_slots_open(bigint[]) to service_role;
revoke all on function public.sb_slot_superseded(bigint, text) from public;
grant execute on function public.sb_slot_superseded(bigint, text) to anon, authenticated, service_role;
