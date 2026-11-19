// AIの財布番 — Cloudflare Worker
//  1) ChatGPT のアプリ一覧向けの中継(中身は Supabase の saifuban-mcp。この住所を名乗らせる)
//  2) /proxy/{anthropic|openai|google|openrouter}/... — APIキー中継(長い応答用)
//     予算の確認・予約と精算は Supabase(saifuban-proxy の関門)が行い、ここは応答を流すだけ。
//     Supabase は1回の処理に時間の上限があるが、ここは応答を流しているあいだ切れないので、何分かかる応答も最後まで届く。
// セルフホストのときは Worker の環境変数で上書きする:
//   SUPABASE_URL   = https://<あなたのプロジェクト>.supabase.co
//   PUBLIC_BASE    = この Worker の住所(例 https://saifuban.<you>.workers.dev)
//   RELAY_SECRET   = (秘密)Supabase の Vault にある saifuban_relay_secret と同じ値
//   OPENAI_CHALLENGE = (任意)ChatGPT のアプリ申請で使うドメイン確認の文字列
let UP = "https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1/saifuban-mcp";
let GATE = "https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1/saifuban-proxy/_relay";
let BASE = "https://saifuban.saifuban-app.workers.dev";
let CHALLENGE = "VAtXTMyo6i_F3bubvyaJtJ4bdGoIYvQdBLI0OkJbfEY"; // OpenAI のドメイン確認用の文字列
function configure(env) {
  if (env.SUPABASE_URL) {
    const sb = env.SUPABASE_URL.replace(/\/$/, "");
    UP = sb + "/functions/v1/saifuban-mcp";
    GATE = sb + "/functions/v1/saifuban-proxy/_relay";
    CHALLENGE = env.OPENAI_CHALLENGE || "";
  }
  if (env.PUBLIC_BASE) BASE = env.PUBLIC_BASE.replace(/\/$/, "");
}
const HEAD_MAX = 1 << 20; // 精算用に残す応答: 先頭1MB
const TAIL_MAX = 8 << 20; //                    と末尾8MB(利用量は先頭と末尾に入っている)

async function proxy(req, env, ctx, u) {
  const m = u.pathname.match(/^\/proxy\/(anthropic|openai|google|openrouter)(\/.*)?$/);
  if (!m) {
    return new Response(JSON.stringify({ error: "use /proxy/{anthropic|openai|google|openrouter}/..." }), { status: 404, headers: { "content-type": "application/json" } });
  }
  if (!env.RELAY_SECRET) return new Response(JSON.stringify({ error: "relay not configured" }), { status: 500, headers: { "content-type": "application/json" } });
  const body = ["GET", "HEAD"].includes(req.method) ? null : await req.arrayBuffer();

  // 1. 関門: 予算の確認と予約。通れば本物のキー入りの送り先が返る
  const gh = new Headers(req.headers);
  gh.delete("host");
  gh.set("x-saifuban-relay", env.RELAY_SECRET);
  gh.set("x-saifuban-method", req.method);
  const g = await fetch(`${GATE}/gate/${m[1]}${m[2] || "/"}${u.search}`, { method: "POST", headers: gh, body });
  if (g.headers.get("x-saifuban-gate") !== "ok") {
    const h = new Headers(g.headers);
    h.delete("content-encoding");
    h.delete("content-length");
    return new Response(g.body, { status: g.status, headers: h });
  }
  const plan = await g.json();

  const settle = (status, bytes, normal, sse, truncated) =>
    fetch(`${GATE}/settle?slot=${plan.slot}&status=${status}&normal=${normal ? 1 : 0}&sse=${sse ? 1 : 0}&truncated=${truncated ? 1 : 0}`, {
      method: "POST",
      headers: { "x-saifuban-relay": env.RELAY_SECRET, "content-type": "application/octet-stream" },
      body: bytes,
    }).catch(() => {}); // 届かなければ、10分後に予約額で計上される

  // 2. APIへ送る
  let up;
  try {
    up = await fetch(plan.url, { method: plan.method, headers: plan.headers, body: plan.body != null ? plan.body : body });
  } catch (e) {
    ctx.waitUntil(settle(0, null, false, false, false));
    return new Response(JSON.stringify({ error: { type: "api_error", message: "[Saifuban] Could not reach the API" } }), { status: 502, headers: { "content-type": "application/json" } });
  }
  const out = new Headers(up.headers);
  out.delete("content-encoding");
  out.delete("content-length");
  out.set("x-saifuban-remaining-jpy", String(plan.remaining_jpy));
  const sse = (up.headers.get("content-type") || "").includes("text/event-stream");
  if (!up.body) {
    ctx.waitUntil(settle(up.status, null, true, sse, false));
    return new Response(null, { status: up.status, headers: out });
  }

  // 3. 応答をそのまま流しつつ、同じものを手元にためて、終わったら精算に送る(中身の解析は Supabase 側)
  const [toClient, toLedger] = up.body.tee();
  ctx.waitUntil((async () => {
    const reader = toLedger.getReader();
    const head = []; let headSize = 0;
    const tail = []; let tailSize = 0;
    let truncated = false, normal = true;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        if (headSize < HEAD_MAX) { head.push(value); headSize += value.byteLength; continue; }
        tail.push(value); tailSize += value.byteLength;
        while (tailSize > TAIL_MAX && tail.length > 1) { tailSize -= tail.shift().byteLength; truncated = true; }
      }
    } catch (e) {
      normal = false;
    }
    const all = new Uint8Array(headSize + tailSize);
    let off = 0;
    for (const c of head) { all.set(c, off); off += c.byteLength; }
    for (const c of tail) { all.set(c, off); off += c.byteLength; }
    await settle(up.status, all, normal, sse, truncated);
  })());
  return new Response(toClient, { status: up.status, headers: out });
}

export default {
  async fetch(req, env, ctx) {
    configure(env);
    const u = new URL(req.url);
    if (u.pathname === "/.well-known/openai-apps-challenge") {
      return new Response(CHALLENGE, { status: CHALLENGE ? 200 : 404, headers: { "content-type": "text/plain; charset=utf-8" } });
    }
    if (u.pathname === "/" && req.method === "GET") return Response.redirect(env.SITE_URL || "https://ut181749ut.github.io/saifuban/", 302);
    if (u.pathname.startsWith("/proxy/") || u.pathname === "/proxy") return proxy(req, env, ctx, u);
    const h = new Headers(req.headers);
    h.delete("host");
    h.set("x-saifuban-base", BASE);
    const init = { method: req.method, headers: h, redirect: "manual" };
    if (!["GET", "HEAD"].includes(req.method)) init.body = await req.arrayBuffer();
    const r = await fetch(UP + u.pathname + u.search, init);
    return new Response(r.body, { status: r.status, headers: r.headers });
  },
};
