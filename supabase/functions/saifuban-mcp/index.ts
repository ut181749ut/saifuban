// AIの財布番 — URLでつなぐMCPサーバー(Streamable HTTP)
// 接続URL: https://<project>.supabase.co/functions/v1/saifuban-mcp/<エージェントキー>
// claude.ai・ChatGPT など、リモートMCPに対応したAIならURLを貼るだけで使える。
// ChatGPTのアプリ一覧向けには、Cloudflare Workers の中継(https://saifuban.saifuban-app.workers.dev/mcp)からも同じものを使う。
const API = Deno.env.get("SUPABASE_URL")! + "/functions/v1/saifuban";
const MAX_WAIT = 45; // リモート接続のタイムアウトに収まるよう待ち時間は短め
// OAuth(コネクタの「接続」ボタンでつなぐ方式)。URLは1本、許可画面はサイト側
const DIRECT = Deno.env.get("SUPABASE_URL")! + "/functions/v1/saifuban-mcp";
// 中継から来たときは、中継の住所を名乗る(ドメイン確認のため。決まった1つの住所だけを受け付ける)
const RELAY = Deno.env.get("SAIFUBAN_PUBLIC_BASE") || "https://saifuban.saifuban-app.workers.dev"; // セルフホスト: 自分の Worker の住所
const CONSENT = (Deno.env.get("SAIFUBAN_SITE_URL") || "https://ut181749ut.github.io/saifuban/").replace(/\/?$/, "/") + "authorize.html";
const RPC = Deno.env.get("SUPABASE_URL")! + "/rest/v1/rpc/";
const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
async function rpc(fn: string, args: Record<string, unknown>) {
  const r = await fetch(RPC + fn, {
    method: "POST",
    headers: { apikey: SRK, Authorization: "Bearer " + SRK, "Content-Type": "application/json" },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(8000),
  });
  return await r.json();
}
type Base = { base: string; resource: string; prmPath: string };
function baseOf(req: Request): Base {
  if (req.headers.get("x-saifuban-base") === RELAY) {
    return { base: RELAY, resource: RELAY + "/mcp", prmPath: "/.well-known/oauth-protected-resource/mcp" };
  }
  return { base: DIRECT, resource: DIRECT, prmPath: "/.well-known/oauth-protected-resource" };
}
const prm = (b: Base) => ({ resource: b.resource, authorization_servers: [b.base], scopes_supported: ["saifuban"], bearer_methods_supported: ["header"], resource_name: "AIの財布番 / Saifuban" });
const asm = (b: Base) => ({
  issuer: b.base,
  authorization_endpoint: b.base + "/authorize",
  token_endpoint: b.base + "/token",
  registration_endpoint: b.base + "/register",
  response_types_supported: ["code"],
  response_modes_supported: ["query"],
  grant_types_supported: ["authorization_code", "refresh_token"],
  code_challenge_methods_supported: ["S256"],
  token_endpoint_auth_methods_supported: ["none"],
  scopes_supported: ["saifuban"],
  subject_types_supported: ["public"],
  service_documentation: "https://github.com/ut181749ut/saifuban",
});
const unauthorized = (b: Base, err?: string) => new Response(JSON.stringify({ error: err || "unauthorized" }), {
  status: 401,
  headers: {
    ...CORS, "Content-Type": "application/json",
    "WWW-Authenticate": `Bearer resource_metadata="${b.base}${b.prmPath}", scope="saifuban"` + (err ? `, error="${err}"` : ""),
  },
});
const oerr = (error: string, status = 400, desc?: string) =>
  new Response(JSON.stringify({ error, ...(desc ? { error_description: desc } : {}) }), { status, headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" } });

async function oauthRoute(req: Request, url: URL, sub: string, b: Base): Promise<Response | null> {
  const J = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" } });
  if (req.method === "GET" && /^\/\.well-known\/oauth-protected-resource/.test(sub)) return J(prm(b));
  if (req.method === "GET" && /^\/\.well-known\/(oauth-authorization-server|openid-configuration)/.test(sub)) return J(asm(b));
  if (sub === "/register" && req.method === "POST") {
    let body: any = {};
    try { body = await req.json(); } catch { return oerr("invalid_client_metadata"); }
    const uris = Array.isArray(body.redirect_uris) ? body.redirect_uris.filter((x: unknown) => typeof x === "string") : [];
    const r = await rpc("oauth_register", { p_redirect_uris: uris, p_name: typeof body.client_name === "string" ? body.client_name : "" });
    if (!r?.client_id) return oerr(r?.error || "invalid_client_metadata");
    return J({ client_id: r.client_id, client_id_issued_at: Math.floor(Date.now() / 1000), client_name: body.client_name || "", redirect_uris: uris,
      token_endpoint_auth_method: "none", grant_types: ["authorization_code", "refresh_token"], response_types: ["code"] }, 201);
  }
  if (sub === "/authorize" && req.method === "GET") {
    const q = url.searchParams;
    if (q.get("response_type") !== "code") return oerr("unsupported_response_type");
    const r = await rpc("oauth_authorize_start", {
      p_client: q.get("client_id") || "", p_redirect: q.get("redirect_uri") || "", p_challenge: q.get("code_challenge") || "",
      p_method: q.get("code_challenge_method") || "", p_state: q.get("state"), p_scope: q.get("scope"),
    });
    if (r?.request_id) return new Response(null, { status: 302, headers: { ...CORS, Location: CONSENT + "?req=" + r.request_id } });
    if (r?.redirect) {
      const u = new URL(r.redirect);
      u.searchParams.set("error", r.error);
      if (r.description) u.searchParams.set("error_description", r.description);
      if (q.get("state")) u.searchParams.set("state", q.get("state")!);
      return new Response(null, { status: 302, headers: { Location: u.toString() } });
    }
    return oerr(r?.error || "invalid_request");
  }
  if (sub === "/token" && req.method === "POST") {
    const ct = req.headers.get("content-type") || "";
    let f: Record<string, string> = {};
    try {
      f = ct.includes("application/json") ? await req.json() : Object.fromEntries(new URLSearchParams(await req.text()));
    } catch { return oerr("invalid_request"); }
    let r: any;
    if (f.grant_type === "authorization_code") {
      r = await rpc("oauth_token_code", { p_client: f.client_id || null, p_code: f.code || "", p_verifier: f.code_verifier || "", p_redirect: f.redirect_uri || null });
    } else if (f.grant_type === "refresh_token") {
      r = await rpc("oauth_token_refresh", { p_client: f.client_id || null, p_refresh: f.refresh_token || "" });
    } else return oerr("unsupported_grant_type");
    if (!r?.access_token) return oerr(r?.error || "invalid_grant");
    return J(r);
  }
  return null;
}

const TOOLS = [
  {
    name: "request_payment",
    description:
      "お金を使う前に必ず呼ぶツール。支払先・金額・理由を財布番に申請し、許可が出たかを返す。" +
      "status が approved のときだけ支払ってよい。pending_approval は持ち主の承認待ちで、まだ支払ってはいけない(持ち主のスマホに通知が届く)。" +
      "denied や expired のときは支払わず、reason をユーザーに伝える。 / " +
      "Call this BEFORE spending any money. Pay only when status is approved. pending_approval means the owner must approve on their phone — do not pay yet. " +
      "When approved, the result includes payment_token: a single-use token that payment tools can verify, so payments made without approval can be refused. " +
      "If the payment is a subscription or renews automatically, set recurring. Before buying something you may already have paid for, call list_payments. " +
      "If you get pending_approval, poll check_payment_status instead of calling request_payment again (a repeat of a pending request returns the same request).",
    inputSchema: {
      type: "object",
      properties: {
        merchant: { type: "string", description: "支払先のサービス名や店名 / merchant or service name (e.g. OpenAI API, AWS)" },
        amount: { type: "number", exclusiveMinimum: 0, description: "支払う金額(税込) / amount to pay, tax included" },
        currency: { type: "string", enum: ["JPY", "USD"], description: "amount の通貨。省略すると持ち主の通貨 / currency of amount; defaults to the owner's currency" },
        reason: { type: "string", description: "なぜこの支払いが必要か。持ち主が承認するときに読む / why this payment is needed (the owner reads this)" },
        recurring: { type: "string", enum: ["none", "week", "month", "year"], description: "サブスク・定期購入・自動更新なら、その間隔を必ず指定する。定期購入は金額に関係なく持ち主の承認が必要 / If this starts or renews a subscription or any recurring charge, set the billing interval. Recurring charges always need the owner's approval, whatever the amount" },
        idempotency_key: { type: "string", maxLength: 200, description: "同じ支払いをやり直すときは同じ値を渡す。新しい申請は作られず、前の申請が返る / Pass the same value when retrying the same payment; the earlier request is returned instead of creating a new one" },
        image_url: { type: "string", maxLength: 500, description: "買う物の写真のURL(https)。持ち主の承認通知に表示される / https URL of a photo of what you are buying, shown in the owner's approval notification" },
        wait_for_approval_seconds: { type: "integer", minimum: 0, maximum: MAX_WAIT, description: `承認待ちのとき待つ秒数(最大${MAX_WAIT}秒) / seconds to wait for approval` },
      },
      required: ["merchant", "amount", "reason"],
    },
    annotations: { title: "支払いを申請する / Request a payment", readOnlyHint: false, destructiveHint: false, openWorldHint: false },
  },
  {
    name: "check_payment_status",
    description: "以前の申請(request_id)が承認されたかを確認する。approved になってから支払うこと。 / Check whether an earlier request was approved. Pay only after it is approved.",
    inputSchema: {
      type: "object",
      properties: {
        request_id: { type: "integer", minimum: 1 },
        wait_seconds: { type: "integer", minimum: 0, maximum: MAX_WAIT },
      },
      required: ["request_id"],
    },
    annotations: { title: "承認されたか確認する", readOnlyHint: true, destructiveHint: false, openWorldHint: false },
  },
  {
    name: "list_payments",
    description: "このAI自身の過去の支払い申請を調べる(二重払い・二重契約を避けるため)。例: 今月すでにSpotifyを承認済みか。 / Look up this agent's own past payment requests, e.g. to check whether a Spotify charge was already approved this month, and avoid paying twice.",
    inputSchema: {
      type: "object",
      properties: {
        merchant: { type: "string", description: "支払先の名前で絞り込む(部分一致) / filter by merchant name (partial match)" },
        days: { type: "integer", minimum: 1, maximum: 365, description: "何日前までさかのぼるか(既定30) / how many days back (default 30)" },
        limit: { type: "integer", minimum: 1, maximum: 100, description: "最大件数(既定20) / max results (default 20)" },
      },
    },
    annotations: { title: "過去の支払いを調べる / List past payments", readOnlyHint: true, destructiveHint: false, openWorldHint: false },
  },
  {
    name: "get_budget",
    description: "このAIが今日・今週・今月あといくら使えるか、1回の上限、自動承認ライン、使ってよい支払先を確認する。 / Check the remaining daily, weekly and monthly budget, per-payment limit, auto-approve amount and allowed merchants.",
    inputSchema: { type: "object", properties: {} },
    annotations: { title: "残りの予算を見る", readOnlyHint: true, destructiveHint: false, openWorldHint: false },
  },
];

async function api(key: string, path: string, init: RequestInit = {}) {
  try {
    const r = await fetch(API + path, {
      ...init,
      headers: { Authorization: "Bearer " + key, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(20000),
    });
    return await r.json();
  } catch (e) {
    return { error: "network_error", message: String(e) };
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function waitFor(key: string, id: number, seconds: number) {
  const until = Date.now() + Math.min(MAX_WAIT, Math.max(0, seconds | 0)) * 1000;
  let last = await api(key, `/status?id=${id}`);
  while (last?.status === "pending_approval" && Date.now() < until) {
    await sleep(Math.min(4000, Math.max(0, until - Date.now())));
    last = await api(key, `/status?id=${id}`);
  }
  return last;
}

function guidance(r: Record<string, any>) {
  if (!r || r.error) return r?.error === "invalid_agent_key"
    ? "接続URLが無効です。持ち主に財布番の画面でURLを発行し直してもらってください。支払いは行わないでください。"
    : "財布番に確認できませんでした。支払いは行わないでください。";
  switch (r.status) {
    case "approved": return "許可されました。この金額・支払先の範囲でのみ支払ってください。payment_token は1回だけ使える支払い許可証です。支払いツールやお店が財布番のトークン確認(/redeem)に対応している場合は必ず渡してください。 / Approved. Pay only this amount to this merchant. payment_token is a single-use proof of approval; pass it to the payment tool or merchant if it verifies Saifuban tokens.";
    case "pending_approval": return `持ち主の承認待ちです(スマホに通知済み)。まだ支払わないでください。後で check_payment_status(request_id=${r.request_id}) で確認してください。`;
    case "expired": return "承認されないまま失効しました。支払わないでください。";
    default: return "却下されました。支払わず、理由をユーザーに伝えてください。";
  }
}

async function callTool(key: string, name: string, args: Record<string, any>) {
  if (name === "request_payment") {
    const recurring = args.recurring && args.recurring !== "none" ? args.recurring : undefined;
    let r = await api(key, "/request", {
      method: "POST",
      body: JSON.stringify(args.amount_jpy != null && args.amount == null
        ? { merchant: args.merchant, amount_jpy: args.amount_jpy, reason: args.reason, recurring, idempotency_key: args.idempotency_key, image_url: args.image_url }
        : { merchant: args.merchant, amount: args.amount, currency: args.currency, reason: args.reason, recurring, idempotency_key: args.idempotency_key, image_url: args.image_url }),
    });
    const dup = Boolean(r?.duplicate);
    if (r?.status === "pending_approval" && args.wait_for_approval_seconds > 0) {
      r = { ...(await waitFor(key, r.request_id, args.wait_for_approval_seconds)), ...(dup ? { duplicate: true } : {}) };
    }
    const note = dup
      ? `これは申請 #${r.request_id} と同じ内容なので、新しい申請は作っていません。 / Same as request #${r.request_id}; no new request was created. `
      : "";
    return { ...r, instruction: note + guidance(r) };
  }
  if (name === "check_payment_status") {
    const r = args.wait_seconds > 0 ? await waitFor(key, args.request_id, args.wait_seconds) : await api(key, `/status?id=${args.request_id}`);
    return { ...r, instruction: guidance(r) };
  }
  if (name === "get_budget") return await api(key, "/budget");
  if (name === "list_payments") {
    const q = new URLSearchParams();
    if (args.merchant) q.set("merchant", String(args.merchant));
    if (args.days) q.set("days", String(args.days));
    if (args.limit) q.set("limit", String(args.limit));
    return await api(key, "/history?" + q.toString());
  }
  return null;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization, mcp-session-id, mcp-protocol-version",
  "Access-Control-Expose-Headers": "mcp-session-id, www-authenticate",
};
const out = (body: unknown, status = 200) =>
  new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { ...CORS, ...(body === null ? {} : { "Content-Type": "application/json; charset=utf-8" }) },
  });

async function handle(key: string, msg: Record<string, any>) {
  const { id, method, params } = msg;
  const ok = (result: unknown) => ({ jsonrpc: "2.0", id, result });
  const err = (code: number, message: string) => ({ jsonrpc: "2.0", id, error: { code, message } });
  switch (method) {
    case "initialize":
      return ok({
        protocolVersion: params?.protocolVersion || "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "saifuban", title: "AIの財布番", version: "0.8.0" },
        instructions: "お金を使う操作(購入・課金・送金・有料APIの追加購入など)の前には必ず request_payment を呼び、approved のときだけ実行してください。サブスク・定期購入なら recurring を指定してください。 / Call request_payment before any spending and proceed only when approved. Set recurring for subscriptions.",
      });
    case "ping":
      return ok({});
    case "tools/list":
      return ok({ tools: TOOLS });
    case "tools/call": {
      if (!key) return ok({
        content: [{ type: "text", text: "財布番のエージェントキーがありません。https://ut181749ut.github.io/saifuban/ で接続URLを発行し、そのURLでつなぐか Authorization: Bearer sbk_... を付けてください。支払いは行わないでください。 / Missing Saifuban agent key. Get your connection URL at https://ut181749ut.github.io/saifuban/ (or send Authorization: Bearer sbk_...). Do not make any payment." }],
        isError: true,
      });
      const r = await callTool(key, params?.name, params?.arguments || {});
      if (r === null) return err(-32602, "unknown tool: " + params?.name);
      return ok({
        content: [{ type: "text", text: JSON.stringify(r, null, 2) }],
        structuredContent: r,
        isError: Boolean(r?.error),
      });
    }
    default:
      return id === undefined || id === null ? null : err(-32601, "Method not found: " + method);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const url = new URL(req.url);
  const b = baseOf(req);
  let sub = url.pathname.replace(/^.*?\/saifuban-mcp/, "").replace(/\/$/, "");
  if (b.base === RELAY && sub === "/mcp") sub = ""; // 中継の /mcp はここ(本体)
  const fromPath = sub.match(/^\/(sbk_[0-9a-f]{48})$/)?.[1];
  if (!fromPath && sub) {
    try {
      const o = await oauthRoute(req, url, sub, b);
      if (o) return o;
    } catch (e) {
      console.error("oauth", e);
      return oerr("server_error", 500);
    }
    return out({ error: "not_found" }, 404);
  }
  const fromHeader = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
  const key = fromPath || (fromHeader.startsWith("sbk_") ? fromHeader : "");
  // URLにキーがない接続はOAuthでつなぐ。接続とツール一覧はログインなしで見せ、
  // ツールを実際に使うとき(tools/call)だけ401で許可画面へ案内する(遅延認証)
  if (key.startsWith("sbk_oa_") && req.method === "POST" && !(await rpc("oauth_token_valid", { p_token: key }).catch(() => false))) {
    return unauthorized(b, "invalid_token");
  }

  if (req.method === "GET") {
    // サーバーからの通知ストリームは使わない
    return new Response(JSON.stringify({ name: "AIの財布番 MCP", ok: Boolean(key) }), {
      status: 405, headers: { ...CORS, "Content-Type": "application/json", Allow: "POST" },
    });
  }
  if (req.method === "DELETE") return out(null, 204);
  if (req.method !== "POST") return out({ error: "method_not_allowed" }, 405);

  let body: unknown;
  try { body = await req.json(); } catch { return out({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400); }
  if (!key) {
    const msgs = Array.isArray(body) ? body : [body];
    if (msgs.some((m: any) => m && m.method === "tools/call")) return unauthorized(b);
  }

  if (Array.isArray(body)) {
    const results = (await Promise.all(body.map((m) => handle(key, m)))).filter(Boolean);
    return results.length ? out(results) : out(null, 202);
  }
  const res = await handle(key, body as Record<string, any>);
  return res ? out(res) : out(null, 202);
});
