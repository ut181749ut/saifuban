-- sb_proxy_begin_v5 also returns the day's utilization and reset time, so the proxy can send Claude Code's 75%/95% spend warnings
CREATE OR REPLACE FUNCTION public.sb_proxy_begin_v5(p_key text, p_provider text, p_model text, p_in_est bigint, p_out_max bigint,
  p_extra_usd numeric DEFAULT 0, p_choices integer DEFAULT 1, p_min_out bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
declare g jsonb; a agents; n int; en boolean; u record; rate numeric; est_usd numeric; est numeric; pb text; sid bigint;
  out_max bigint := p_out_max; filled boolean := false; ch integer := greatest(1, least(coalesce(p_choices, 1), 16));
  extra numeric := greatest(coalesce(p_extra_usd, 0), 0); avail numeric; lo bigint; hi bigint; mid bigint; orig bigint; shrunk boolean := false;
  reset_at timestamptz; period text;
begin
  a := sb_agent_by_key(p_key);
  if a.id is not null then
    perform 1 from agents where id = a.id for update;  -- 同じAIの呼び出しはここで一列に並ぶ
    perform sb_proxy_expire(a.id);
  end if;
  g := sb_proxy_begin(p_key, p_provider);
  if g ? 'error' then return g; end if;
  en := g->>'lang' = 'en';
  select count(*) into n from proxy_inflight where agent_id = a.id and settled_at is null;
  if n >= a.max_concurrent then
    return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'wait',
      'reason', case when en then format('Too many requests at once (limit %s). Wait for the others to finish', a.max_concurrent)
                     else format('同時に流せる数(%s件)を超えています。ほかの処理が終わるまで待ってください', a.max_concurrent) end);
  end if;
  if out_max < 0 then
    out_max := least(coalesce(sb_max_output(p_provider, p_model), 32768), 32768);
    filled := true;
  end if;
  orig := out_max;
  select usd_jpy into rate from settings where id = 1;
  est_usd := sb_proxy_estimate_usd(p_provider, p_model, p_in_est, out_max * ch) + extra;
  est := greatest(1, ceil(est_usd * rate));
  select * into u from sb_usage(a.id);
  avail := a.daily - u.spent - u.reserved;
  reset_at := ((sb_today(a.id) + 1)::timestamp at time zone sb_agent_tz(a.id));
  if est > avail then
    if u.reserved > 0 and u.spent + est <= a.daily then
      return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'wait',
        'reason', case when en then format('Other calls are still running and have %s reserved. This call (up to %s) fits once they finish. Retry shortly', sb_money_for(a.owner_id, u.reserved), sb_money_for(a.owner_id, est))
                       else format('ほかの呼び出しが%sを予約中です。終わればこの呼び出し(最大%s)は予算内に収まるので、少し待ってやり直してください', sb_money_for(a.owner_id, u.reserved), sb_money_for(a.owner_id, est)) end);
    end if;
    if coalesce(p_min_out, 0) > 0 and out_max > p_min_out
       and ceil((sb_proxy_estimate_usd(p_provider, p_model, p_in_est, p_min_out * ch) + extra) * rate) <= avail then
      lo := p_min_out; hi := out_max - 1;
      while lo < hi loop
        mid := (lo + hi + 1) / 2;
        if ceil((sb_proxy_estimate_usd(p_provider, p_model, p_in_est, mid * ch) + extra) * rate) <= avail then lo := mid; else hi := mid - 1; end if;
      end loop;
      out_max := lo; shrunk := true;
      est_usd := sb_proxy_estimate_usd(p_provider, p_model, p_in_est, out_max * ch) + extra;
      est := greatest(1, ceil(est_usd * rate));
    else
      return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'budget', 'period', 'daily', 'reset_at', reset_at,
        'reason', case when en then format('Daily budget reached: this call could cost up to %s and %s is left. Resets at %s', sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(avail))), to_char(reset_at at time zone sb_agent_tz(a.id), 'YYYY-MM-DD HH24:MI'))
                       else format('この呼び出しは最大%sかかる可能性があり、1日の予算を超えます(残り%s)。%sにリセットされます', sb_money_for(a.owner_id, est), sb_money_for(a.owner_id, greatest(0, floor(avail))), to_char(reset_at at time zone sb_agent_tz(a.id), 'MM/DD HH24:MI')) end);
    end if;
  end if;
  pb := sb_period_block(a, est, en);
  if pb is not null then
    period := case when pb ilike '%week%' or pb like '%週%' then 'weekly' else 'monthly' end;
    reset_at := (case when period = 'weekly' then sb_week_start(a.id) + 7 else (sb_month_start(a.id) + interval '1 month')::date end)::timestamp at time zone sb_agent_tz(a.id);
    return jsonb_build_object('error','blocked','lang', g->>'lang', 'status', 429, 'kind', 'budget', 'period', period, 'reset_at', reset_at,
      'reason', pb || case when en then format('. Resets at %s', to_char(reset_at at time zone sb_agent_tz(a.id), 'YYYY-MM-DD HH24:MI'))
                       else format('。%sにリセットされます', to_char(reset_at at time zone sb_agent_tz(a.id), 'MM/DD HH24:MI')) end);
  end if;
  insert into proxy_inflight (agent_id, reserved_jpy, provider, model) values (a.id, est, p_provider, p_model) returning id into sid;
  return g || jsonb_build_object('slot', sid, 'reserved_jpy', est, 'estimate_usd', est_usd,
    'out_max', case when filled or shrunk then out_max end,
    'shrunk_from', case when shrunk then orig end,
    'remaining_jpy', floor(a.daily - u.spent - u.reserved - est),
    -- 1日の予算のうち、使った分+予約中の分の割合(この呼び出しの予約も含めて多めに)。Claude Code の警告表示に使う
    'util', least(0.99, round((u.spent + u.reserved + est) / nullif(a.daily, 0), 2)),
    'reset_epoch', floor(extract(epoch from reset_at))::bigint);
end $function$;
