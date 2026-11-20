// AIの財布番 API — AIエージェントが呼ぶ窓口
// 認証: Authorization: Bearer sbk_... (エージェントキー)。キーはDB側でSHA-256照合。
// POST /saifuban/request {merchant, amount, currency?("JPY"|"USD"), reason}  ※amount_jpy / amount_usd も可
// GET  /saifuban/status?id=123
// GET  /saifuban/budget
// POST /saifuban/decide?id=123&t=<通知のトークン>&a=1|0   (スマホ通知のボタンから)
// POST /saifuban/redeem {token, merchant?, amount?, currency?}   支払う側が使い捨てトークンを確認して使用済みにする
// POST /saifuban/verify {token, merchant?, amount?, currency?}   確認だけ(使用済みにしない)
// POST /saifuban/budget-alert {agent}   API中継が予算切れで止めたとき(データベースから、合言葉つきで呼ばれる)。持ち主に通知を出す
// POST /saifuban/boost?a=<AIのid>&t=<通知のトークン>   通知のボタンから: 今日だけ予算を足す
// GET  /saifuban/history?merchant=&days=30&limit=20   このAI自身の過去の申請(二重払い・二重契約の確認用)
// request の recurring: "week" | "month" | "year" を付けると定期購入として扱い、金額に関係なく必ず持ち主に聞く
// request の idempotency_key: 同じ値のやり直しは新しい申請を作らず前の申請を返す(承認待ちと同じ内容の申請は印がなくても前のものを返す)
// 金額は円に直して1円未満を切り上げる(予算を少しでも超える額が許可されないように)
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { sendPush } from "./push.ts";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);
const SELF = Deno.env.get("SUPABASE_URL")! + "/functions/v1/saifuban";
const NTFY = "https://ntfy.sh";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization, x-agent-key",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", ...(status === 429 ? { "Retry-After": "60" } : {}) },
  });

const ERR_STATUS: Record<string, number> = {
  invalid_agent_key: 401,
  request_not_found: 404,
  merchant_required: 400,
  amount_must_be_positive: 400,
  not_pending: 409,
  rate_limited: 429,
};

async function call(fn: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(fn, args);
  if (error) {
    console.error(fn, error);
    return { error: "server_error" } as Record<string, unknown>;
  }
  return data as Record<string, unknown>;
}
const respond = (data: Record<string, unknown>) =>
  json(data, data && "error" in data ? (ERR_STATUS[String(data.error)] ?? (data.error === "server_error" ? 500 : 400)) : 200);

const yen = (n: unknown) => "¥" + Math.round(Number(n) || 0).toLocaleString("ja-JP");
// 内部はすべて円。ドルを選んだ持ち主には、表示と入力だけドルに換算する
type Prefs = { lang?: string; currency?: string; rate?: number | string };
const isUSD = (p: Prefs) => p?.currency === "USD";
const rateOf = (p: Prefs) => Number(p?.rate) || 155;
const money = (n: unknown, p: Prefs) =>
  isUSD(p) ? "$" + ((Number(n) || 0) / rateOf(p)).toFixed(2) : yen(n);
async function prefsForKey(key: string): Promise<Prefs> {
  const { data } = await db.rpc("sb_key_prefs", { p_key: key });
  return (data ?? {}) as Prefs;
}
// 円の項目(..._jpy)にドルの値を並べて付ける
function withUsd(r: Record<string, unknown>, p: Prefs) {
  if (!r || "error" in r || !isUSD(p)) return r;
  const out: Record<string, unknown> = { ...r, currency: "USD", usd_jpy_rate: rateOf(p) };
  for (const [k, v] of Object.entries(r)) {
    if (k.endsWith("_jpy") && typeof v === "number") out[k.replace(/_jpy$/, "_usd")] = Math.round((v / rateOf(p)) * 100) / 100;
    if (k.endsWith("_jpy") && typeof v === "string" && v !== "" && !isNaN(Number(v))) out[k.replace(/_jpy$/, "_usd")] = Math.round((Number(v) / rateOf(p)) * 100) / 100;
  }
  return out;
}

// 承認済みなら、使い捨ての支払いトークンを添える(支払う側が /redeem で確かめる)
async function withToken(key: string, r: Record<string, unknown>) {
  if (!r || "error" in r || r.status !== "approved" || !r.request_id) return r;
  const { data } = await db.rpc("sb_issue_token", { p_key: key, p_id: Number(r.request_id) });
  return data ? { ...r, ...data } : r;
}

async function redeem(req: Request, consume: boolean) {
  let b: Record<string, unknown> = {};
  try { b = await req.json(); } catch { return json({ valid: false, error: "invalid_json" }, 400); }
  const token = String(b.token ?? b.payment_token ?? "");
  const merchant = typeof b.merchant === "string" ? b.merchant : null;
  let amountJpy: number | null = null;
  if (b.amount_jpy != null) amountJpy = Number(b.amount_jpy);
  else if (b.amount != null || b.amount_usd != null) {
    const cur = b.amount_usd != null ? "USD" : String(b.currency ?? "JPY").toUpperCase();
    const amt = Number(b.amount_usd ?? b.amount);
    if (cur === "USD") {
      const { data: s } = await db.from("settings").select("usd_jpy").eq("id", 1).single();
      amountJpy = amt * (Number(s?.usd_jpy) || 155);
    } else if (cur === "JPY") amountJpy = amt;
    else return json({ valid: false, error: "unsupported_currency", supported: ["JPY", "USD"] }, 400);
  }
  if (amountJpy != null && (!Number.isFinite(amountJpy) || amountJpy <= 0)) return json({ valid: false, error: "bad_amount" }, 400);
  const by = (req.headers.get("user-agent") ?? "").slice(0, 120);
  const r = await call("sb_redeem_token", { p_token: token, p_merchant: merchant, p_amount_jpy: amountJpy, p_consume: consume, p_by: by });
  if (!r || r.error === "server_error") return json({ valid: false, error: "server_error" }, 500);
  if (!r.valid) return json(r, 200);
  const { prefs, ...out } = r as Record<string, any>;
  return json(withUsd(out, prefs ?? {}));
}

async function ntfy(body: Record<string, unknown>) {
  try {
    const r = await fetch(NTFY, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(6000),
    });
    if (!r.ok) console.error("ntfy", r.status, await r.text());
  } catch (e) {
    console.error("ntfy", e);
  }
}

// 承認待ちになった申請をスマホに通知(ボタンでそのまま承認・却下できる)
const MSG = {
  ja: {
    pending: (amt: string, m: string) => `承認待ち ${amt} · ${m}`,
    pendingRec: (amt: string, m: string) => `定期購入の承認待ち ${amt} · ${m}`,
    per: { week: "/週", month: "/月", year: "/年", unknown: "" } as Record<string, string>,
    annual: (amt: string) => `年間 ${amt}`,
    maybeRec: "定期購入の可能性があります",
    first: "初めての支払先",
    body: (agent: string, reason: string) => `${agent} からの申請\n理由: ${reason || "(なし)"}`,
    approve: "承認する", reject: "却下", open: "画面で見る",
    approved: "承認しました", rejected: "却下しました", already: "この申請はもう判断済みです", req: (id: number) => `申請 #${id}`,
  },
  en: {
    pending: (amt: string, m: string) => `Approval needed ${amt} · ${m}`,
    pendingRec: (amt: string, m: string) => `Subscription approval ${amt} · ${m}`,
    per: { week: "/wk", month: "/mo", year: "/yr", unknown: "" } as Record<string, string>,
    annual: (amt: string) => `${amt} per year`,
    maybeRec: "This may be a subscription",
    first: "First payment to this merchant",
    body: (agent: string, reason: string) => `Request from ${agent}\nReason: ${reason || "(none)"}`,
    approve: "Approve", reject: "Reject", open: "Open app",
    approved: "Approved", rejected: "Rejected", already: "This request was already decided", req: (id: number) => `Request #${id}`,
  },
};
const msgs = (l: unknown) => (l === "en" ? MSG.en : MSG.ja);

async function notifyPending(id: number) {
  const n = await call("sb_notify_prepare", { p_id: id });
  if (!n || n.skip || n.error) return;
  const L = msgs(n.lang);
  const base = `${SELF}/decide?id=${n.id}&t=${n.token}`;
  const P = { currency: n.currency as string, rate: n.rate as number };
  const rec = typeof n.recurring === "string" ? n.recurring : null;
  const mult: Record<string, number> = { week: 52, month: 12, year: 1 };
  const amt = money(n.amount, P) + (rec ? (L.per[rec] ?? "") : "");
  const title = rec ? L.pendingRec(amt, String(n.merchant)) : L.pending(amt, String(n.merchant));
  const extra: string[] = [];
  if (rec && mult[rec]) extra.push(L.annual(money(Number(n.amount) * mult[rec], P)));
  if (rec === "unknown") extra.push(L.maybeRec);
  if (n.first_merchant) extra.push(L.first);
  const body = L.body(String(n.agent), String(n.reason ?? "")) + (extra.length ? "\n" + extra.join(" · ") : "");
  const jobs: Promise<unknown>[] = [];
  if (Array.isArray(n.push) && n.push.length) {
    jobs.push(sendPush(db, n.push, {
      type: "pending", id: n.id, title, body, lang: n.lang === "en" ? "en" : "ja",
      short: `${n.merchant} ${amt}`,
      approve_url: `${base}&a=1`, reject_url: `${base}&a=0`, app_url: n.app_url,
    }).catch((e) => console.error("push", e)));
  }
  if (n.topic) {
    jobs.push(ntfy({
      topic: n.topic, title, message: n.lang === "en" ? body : `${body}\n${n.note}`, priority: 4, tags: ["moneybag"], click: n.app_url,
      actions: [
        { action: "http", label: L.approve, url: `${base}&a=1`, method: "POST", clear: true },
        { action: "http", label: L.reject, url: `${base}&a=0`, method: "POST", clear: true },
        { action: "view", label: L.open, url: n.app_url },
      ],
    }));
  }
  await Promise.all(jobs);
}

// 予算切れの通知(「今日だけ+500円」のボタン付き)。ボタンの合言葉は持ち主の通知にだけ載り、AIには渡らない
let RELAY_SECRET = "";
async function relayOk(req: Request) {
  if (!RELAY_SECRET) { const { data } = await db.rpc("sb_relay_secret"); RELAY_SECRET = typeof data === "string" ? data : ""; }
  const got = req.headers.get("x-saifuban-relay") || "";
  if (RELAY_SECRET.length < 32 || got.length !== RELAY_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ RELAY_SECRET.charCodeAt(i);
  return diff === 0;
}
async function budgetAlert(req: Request) {
  if (!(await relayOk(req))) return json({ error: "forbidden" }, 403);
  let b: Record<string, unknown> = {};
  try { b = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const n = await call("sb_budget_alert_prepare", { p_agent: String(b.agent ?? "") });
  if (!n || n.skip || n.error) return json({ ok: true, skipped: true });
  const en = n.lang === "en";
  const P = { currency: n.currency as string, rate: n.rate as number };
  const plus = money(n.boost, P);
  const boostUrl = `${SELF}/boost?a=${n.agent_id}&t=${n.token}`;
  const title = en ? `${n.agent} hit today's budget` : `${n.agent} が今日の予算に達しました`;
  const body = en ? `Stopped at the daily budget of ${money(n.daily, P)}. Tap "+${plus} today" to keep going.` : `1日の予算(${money(n.daily, P)})に達したので止めました。続けるなら「今日だけ+${plus}」を押してください。`;
  const label = en ? `+${plus} today` : `今日だけ+${plus}`;
  const jobs: Promise<unknown>[] = [];
  if (Array.isArray(n.push) && n.push.length) {
    jobs.push(sendPush(db, n.push, { type: "budget", id: `budget-${n.agent_id}`, title, body, lang: en ? "en" : "ja", boost_url: boostUrl, boost_label: label, short: plus, app_url: n.app_url })
      .catch((e) => console.error("push", e)));
  }
  if (n.topic) {
    jobs.push(ntfy({ topic: n.topic, title, message: body, priority: 4, tags: ["moneybag"], click: n.app_url,
      actions: [{ action: "http", label, url: boostUrl, method: "POST", clear: true }, { action: "view", label: en ? "Open app" : "画面で見る", url: n.app_url }] }));
  }
  await Promise.all(jobs);
  return json({ ok: true });
}
async function boost(url: URL) {
  const a = url.searchParams.get("a") ?? "", t = url.searchParams.get("t") ?? "";
  if (!/^[0-9a-f-]{36}$/i.test(a) || !/^[0-9a-f]{48}$/.test(t)) return json({ ok: false, error: "bad_request" }, 400);
  const r = await call("sb_boost", { p_agent: a, p_token: t });
  if (!r || r.error === "server_error") return json({ ok: false, error: "server_error" }, 500);
  const { owner_id: owner, ...out } = r as Record<string, any>;
  if (out.ok) {
    const { data: topic } = await db.rpc("sb_owner_topic", { p_owner: owner ?? null });
    if (topic) await ntfy({ topic, title: out.lang === "en" ? "Budget raised for today" : "今日の予算を足しました",
      message: `${out.agent} +${money(out.amount, out)}`, priority: 2, tags: ["white_check_mark"] });
  }
  return json(out, out.ok ? 200 : 409);
}

async function decideFromNotification(url: URL) {
  const id = Number(url.searchParams.get("id"));
  const token = url.searchParams.get("t") ?? "";
  const approve = url.searchParams.get("a") === "1";
  if (!Number.isInteger(id) || id <= 0 || !/^[0-9a-f]{48}$/.test(token)) return json({ error: "bad_request" }, 400);
  const r = await call("sb_decide_token", { p_id: id, p_token: token, p_approve: approve });
  const { data: topic } = r.ok ? await db.rpc("sb_owner_topic", { p_owner: r.owner_id ?? null }) : { data: null };
  if (topic) {
    const { data: pr } = await db.rpc("sb_owner_prefs", { p_owner: r.owner_id ?? null });
    const L = msgs(pr?.lang);
    await ntfy({
      topic,
      title: r.ok ? (approve ? L.approved : L.rejected) : L.already,
      message: r.ok ? `${r.merchant} ${money(r.amount, pr ?? {})}` : L.req(id),
      priority: 2,
      tags: [r.ok ? (approve ? "white_check_mark" : "x") : "information_source"],
    });
  }
  const { owner_id: _owner, ...out } = r;
  return respond(out);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const url = new URL(req.url);
  const route = url.pathname.replace(/^.*\/saifuban/, "").replace(/\/$/, "") || "/";

  try {
    if (route === "/decide" && req.method === "POST") return await decideFromNotification(url);
    if (route === "/redeem" && req.method === "POST") return await redeem(req, true);
    if (route === "/verify" && req.method === "POST") return await redeem(req, false);
    if (route === "/budget-alert" && req.method === "POST") return await budgetAlert(req);
    if (route === "/boost" && req.method === "POST") return await boost(url);

    const auth = req.headers.get("authorization") ?? "";
    const key = auth.replace(/^Bearer\s+/i, "").trim() || req.headers.get("x-agent-key") || "";
    if (!key.startsWith("sbk_")) return json({ error: "invalid_agent_key" }, 401);

    if (route === "/request" && req.method === "POST") {
      let body: Record<string, unknown> = {};
      try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
      const p = await prefsForKey(key);
      // 通貨: amount_jpy / amount_usd / amount + currency(省略時は持ち主の通貨)
      let amount: number;
      if (body.amount_jpy != null) amount = Number(body.amount_jpy);
      else if (body.amount_usd != null) amount = Number(body.amount_usd) * rateOf(p);
      else {
        const cur = String(body.currency ?? (isUSD(p) ? "USD" : "JPY")).toUpperCase();
        if (cur !== "USD" && cur !== "JPY") return json({ error: "unsupported_currency", supported: ["JPY", "USD"] }, 400);
        amount = Number(body.amount) * (cur === "USD" ? rateOf(p) : 1);
      }
      if (!Number.isFinite(amount) || amount <= 0 || amount > 100_000_000) {
        return json({ error: "amount_must_be_positive" }, 400);
      }
      // 定期購入: recurring に "week" | "month" | "year"(true や interval でも可)
      const recRaw = typeof body.recurring === "string" ? body.recurring : body.recurring === true ? String(body.interval ?? "unknown") : "";
      const rec = ["week", "month", "year"].includes(recRaw.toLowerCase()) ? recRaw.toLowerCase() : null;
      // 同じ申請のやり直しは前の申請を返す(承認待ちのものは自動で、idempotency_key があれば状態に関係なく)
      const idem = typeof body.idempotency_key === "string" ? body.idempotency_key.slice(0, 200) : null;
      const r = await call("sb_request_v3", {
        p_key: key,
        p_merchant: String(body.merchant ?? ""),
        p_amount: Math.max(1, Math.ceil(amount - 1e-9)),
        p_reason: String(body.reason ?? "") + (body.recurring === true && !rec ? " (subscription)" : ""),
        p_recurring: rec,
        p_idem: idem,
      });
      if (r && r.status === "pending_approval" && !r.duplicate) await notifyPending(Number(r.request_id));
      return respond(withUsd(await withToken(key, r), p));
    }
    if (route === "/status" && req.method === "GET") {
      const id = Number(url.searchParams.get("id"));
      if (!Number.isInteger(id) || id <= 0) return json({ error: "request_not_found" }, 404);
      const [r, p] = await Promise.all([call("sb_status", { p_key: key, p_id: id }), prefsForKey(key)]);
      return respond(withUsd(await withToken(key, r), p));
    }
    if (route === "/budget" && req.method === "GET") {
      const [r, p] = await Promise.all([call("sb_budget", { p_key: key }), prefsForKey(key)]);
      return respond(withUsd(r, p));
    }
    if (route === "/history" && req.method === "GET") {
      const [r, p] = await Promise.all([call("sb_history", {
        p_key: key,
        p_merchant: url.searchParams.get("merchant") ?? "",
        p_days: Number(url.searchParams.get("days")) || 30,
        p_limit: Number(url.searchParams.get("limit")) || 20,
      }), prefsForKey(key)]);
      if (r && Array.isArray(r.payments)) r.payments = (r.payments as Record<string, unknown>[]).map((x) => withUsd(x, p));
      return respond(r);
    }
    return json({ error: "not_found", routes: ["POST /request", "GET /status?id=", "GET /budget", "GET /history"] }, 404);
  } catch (e) {
    console.error(e);
    return json({ error: "server_error" }, 500);
  }
});
