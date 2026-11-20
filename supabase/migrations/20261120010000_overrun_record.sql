-- When the actual cost of a call comes in above its reservation, it is still charged in full (the ledger stays right),
-- but the overrun is recorded on the slot and shown on the request line, so it doesn't hide in the daily total.
alter table public.proxy_inflight add column if not exists overrun_jpy numeric;

create or replace function public.sb_owner_of_agent(p_agent uuid) returns uuid language sql stable security definer set search_path to 'public'
as $$ select owner_id from agents where id = p_agent $$;
revoke all on function public.sb_owner_of_agent(uuid) from public, anon, authenticated;

create or replace function public.sb_proxy_settle(p_slot bigint, p_provider text, p_model text, p_in bigint, p_out bigint, p_cache_write bigint, p_cache_read bigint, p_cost_usd numeric, p_basis text default 'usage'::text, p_extra_usd numeric default 0, p_extra_note text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s proxy_inflight; c record; d date; over numeric;
begin
  select * into s from proxy_inflight where id = p_slot for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_slot'); end if;
  d := (s.started_at at time zone sb_agent_tz(s.agent_id))::date;
  if s.settled_at is not null then
    if s.basis in ('expired', 'cancelled') and p_basis = 'usage' then
      select * into c from sb_proxy_charge(s.agent_id, p_provider, p_model, p_in, p_out, p_cache_write, p_cache_read, p_cost_usd, null, d, p_extra_usd, p_extra_note);
      delete from requests where id = s.request_id;
      over := case when c.jpy > s.reserved_jpy then round(c.jpy - s.reserved_jpy, 2) end;
      if over is not null then update requests set note = note || format(' · 予約超過 +%s', sb_money_for(sb_owner_of_agent(s.agent_id), over)) where id = c.rid; end if;
      update proxy_inflight set settled_jpy = c.jpy, request_id = c.rid, basis = 'usage_late', overrun_jpy = over where id = p_slot;
      return jsonb_build_object('ok', true, 'corrected', true, 'jpy', c.jpy, 'was', s.settled_jpy, 'day', d, 'overrun_jpy', over);
    end if;
    return jsonb_build_object('ok', true, 'duplicate', true, 'jpy', s.settled_jpy, 'basis', s.basis);
  end if;
  select * into c from sb_proxy_charge(s.agent_id, p_provider, p_model, p_in, p_out, p_cache_write, p_cache_read, p_cost_usd,
    case when p_basis = 'cancelled' then 'API利用(途中で切断・届いた分から見積もり)' end, d, p_extra_usd, p_extra_note);
  over := case when c.jpy > s.reserved_jpy then round(c.jpy - s.reserved_jpy, 2) end;
  if over is not null then update requests set note = note || format(' · 予約超過 +%s', sb_money_for(sb_owner_of_agent(s.agent_id), over)) where id = c.rid; end if;
  update proxy_inflight set settled_at = now(), settled_jpy = c.jpy, request_id = c.rid, basis = p_basis, overrun_jpy = over where id = p_slot;
  return jsonb_build_object('ok', true, 'jpy', c.jpy, 'basis', p_basis, 'day', d, 'overrun_jpy', over);
end $function$;
