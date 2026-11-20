// AIの財布番 — APIキー中継(強制力)
// AIには本物のAPIキーを渡さず、財布番のエージェントキー(sbk_...)を渡す。
// AIはこの中継を通してしか Anthropic / OpenAI / Google Gemini / OpenRouter を呼べないので、予算を超えたら確実に止まる。
//
//   Anthropic: ベースURL = .../functions/v1/saifuban-proxy/anthropic   (x-api-key: sbk_...)
//   OpenAI   : ベースURL = .../functions/v1/saifuban-proxy/openai/v1   (Authorization: Bearer sbk_...)
//   Gemini   : ベースURL = .../functions/v1/saifuban-proxy/google/v1beta/openai (OpenAI互換) または .../google (Google純正の形式)
//   OpenRouter: ベースURL = .../functions/v1/saifuban-proxy/openrouter/v1  (何百種類ものモデルを1つのキーで)
//
// 呼び出しの前に「予算が残っているか・使ってよい支払先か・緊急停止中でないか・同時に流せる数を超えていないか」を確認し、
// この呼び出しで「かかりうる最大額」(入力の大きさ+出力の上限×単価)を予約してから流す。
// 返ってきた実際のトークン数(とウェブ検索などの回数)から利用料を計算して記録し、予約を外す(予約→精算)。
// 同時にいくつ流しても、予約済みの額と合わせて予算と比べるので、上限を超えて通ることはない。
//
// 長い応答のための中継(Cloudflare Worker)からも使う:
//   POST .../saifuban-proxy/_relay/gate/{provider}/...   予算の確認と予約。本物のキー入りの「送り先」を返す(合言葉が必要)
//   POST .../saifuban-proxy/_relay/settle?slot=...       Worker が受け取った応答を丸ごと送り、精算する(合言葉が必要)
// ここ(Supabase)は1回の処理に時間の上限があるが、Worker は応答を流しているあいだ切れないので、長い応答も最後まで届く。
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const UPSTREAM: Record<string, string> = {
  anthropic: "https://api.anthropic.com",
  openai: "https://api.openai.com",
  google: "https://generativelanguage.googleapis.com",
  openrouter: "https://openrouter.ai/api",
};

type Usage = {
  model: string; input: number; output: number; cacheWrite: number; cacheRead: number; cost: number | null; seen: boolean;
  // トークン以外にかかる料金(ウェブ検索など)。回数を数えて、精算のときに足す
  searches: number; toolIds: Set<string>; fileSearches: number; groundedQueries: number; grounded: boolean;
  // 最後の利用量(出力トークンの確定値)まで届いたか。届かずに切れたら、見積もり額で計上する
  final: boolean;
  // 実際に流れてきた出力の量(バイト)。途中で切れたときの見積もりに使う
  outBytes: number;
};
const newUsage = (model: string): Usage => ({ model, input: 0, output: 0, cacheWrite: 0, cacheRead: 0, cost: null, seen: false,
  searches: 0, toolIds: new Set(), fileSearches: 0, groundedQueries: 0, grounded: false, final: false, outBytes: 0 });
const enc = new TextEncoder();
const bytes = (v: unknown) => (typeof v === "string" ? enc.encode(v).length : 0);
// ストリームの1イベントに入っている「書かれた出力」の量を数える(本文・考えた内容・ツールの引数)
function deltaBytes(o: Record<string, any>): number {
  let n = 0;
  const d = o.delta;
  if (d && typeof d === "object") n += bytes(d.text) + bytes(d.thinking) + bytes(d.partial_json); // Anthropic
  else if (typeof d === "string" && /delta/.test(String(o.type || ""))) n += bytes(d); // OpenAI Responses
  for (const c of Array.isArray(o.choices) ? o.choices : []) { // OpenAI Chat
    const cd = c?.delta || {};
    n += bytes(cd.content) + bytes(cd.reasoning) + bytes(cd.reasoning_content);
    for (const t of Array.isArray(cd.tool_calls) ? cd.tool_calls : []) n += bytes(t?.function?.arguments);
  }
  for (const c of Array.isArray(o.candidates) ? o.candidates : []) { // Google
    for (const pt of Array.isArray(c?.content?.parts) ? c.content.parts : []) n += bytes(pt?.text) + (pt?.functionCall ? bytes(JSON.stringify(pt.functionCall)) : 0);
  }
  return n;
}
// 途中で切れた呼び出しの金額: 実際に流れた分から多めに見積もる(予約額が上限)
//   入力 = 届いた利用量(Anthropic は最初に届く)か、本文の大きさからの見積もり
//   出力 = 届いた利用量か、流れた文字の量÷2.5(多めに数える)の大きい方 + 切断の前後で書かれていた分の余裕(1割か256の大きい方)
async function cutUsage(provider: string, model: string, u: Usage, estInTokens: number, estUsd: number): Promise<Usage> {
  const inTok = Math.max(u.input + u.cacheRead + u.cacheWrite, u.seen ? 0 : estInTokens) || estInTokens;
  const seenOut = Math.max(u.output, Math.ceil(u.outBytes / 2.5));
  const outTok = seenOut + Math.max(256, Math.ceil(seenOut * 0.1));
  let usd = estUsd;
  try {
    const { data } = await db.rpc("sb_proxy_estimate_usd", { p_provider: provider, p_model: model, p_in: inTok, p_out: outTok });
    const v = Number(data);
    if (Number.isFinite(v) && v >= 0) usd = Math.min(v, estUsd);
  } catch { /* 見積もれなければ予約額 */ }
  return { ...newUsage(`${model || "unknown"} (cut: estimated from what streamed)`), input: inTok, output: outTok, cost: usd, seen: true };
}

// トークン以外の料金(USD)。各社の公開価格(2026年11月時点)。迷う場合は高い方で数える
//   Anthropic のウェブ検索: 1回 $0.01 / OpenAI のウェブ検索: 1回 最大 $0.025 / OpenAI のファイル検索: 1回 $0.0025
//   Google の検索グラウンディング: Gemini 3 以降は検索1回 $0.014、それより前は1回の呼び出しにつき $0.035
const FEE = { anthropicSearch: 0.01, openaiSearch: 0.025, openaiFileSearch: 0.0025, geminiQuery: 0.014, geminiPrompt: 0.035 };
function extraUsd(provider: string, u: Usage): number {
  if (provider === "openrouter") return 0; // OpenRouter は実際の金額(検索込み)を返す
  if (provider === "anthropic") return u.searches * FEE.anthropicSearch;
  if (provider === "openai") {
    // 検索付きモデル(gpt-4o-search-preview など)は、検索の記録がなくても1回分を数える
    const s = u.searches || (/search/.test(u.model) ? 1 : 0);
    return s * FEE.openaiSearch + u.fileSearches * FEE.openaiFileSearch;
  }
  if (provider === "google") {
    if (/gemini-[3-9]|gemini-\d{2}/.test(u.model)) return u.groundedQueries * FEE.geminiQuery;
    return u.grounded ? FEE.geminiPrompt : 0;
  }
  return 0;
}
// 予約のとき: 検索ツールを渡していれば、検索の分も「かかりうる最大額」に入れる(回数の上限がなければ10回とみなす)
function extraEstimateUsd(provider: string, model: string, body: Record<string, any> | null): number {
  const tools: any[] = Array.isArray(body?.tools) ? body!.tools : [];
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.min(Math.ceil(v), 100) : 10);
  let usd = 0;
  for (const t of tools) {
    const type = String(t?.type ?? "");
    if (provider === "anthropic" && type.startsWith("web_search")) usd += n(t.max_uses) * FEE.anthropicSearch;
    if (provider === "openai" && type.startsWith("web_search")) usd += 10 * FEE.openaiSearch;
    if (provider === "openai" && type === "file_search") usd += 10 * FEE.openaiFileSearch;
    if (provider === "google" && (t?.googleSearch || t?.google_search || t?.googleSearchRetrieval)) {
      usd += /gemini-[3-9]|gemini-\d{2}/.test(model) ? 10 * FEE.geminiQuery : FEE.geminiPrompt;
    }
  }
  // OpenAI の検索付きモデル(gpt-4o-search-preview など)は、呼び出しごとに検索が入る
  if (provider === "openai" && /search/.test(model)) usd += FEE.openaiSearch;
  return usd;
}

// 検索・取得の結果は「入力」として請求される。予約のときに、その分の入力も見込む
//   Anthropic のウェブ検索: 1回あたり最大 8,000 トークン / ウェブ取得: 1回あたり max_content_tokens(なければ 25,000)
//   OpenAI のウェブ検索: 1回あたり 8,000 トークン(回数の上限が分からないので10回)
function toolInputTokens(provider: string, body: Record<string, any> | null): number {
  const tools: any[] = Array.isArray(body?.tools) ? body!.tools : [];
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.min(Math.ceil(v), 100) : 10);
  let t = 0;
  for (const x of tools) {
    const type = String(x?.type ?? "");
    if (provider === "anthropic" && type.startsWith("web_search")) t += n(x.max_uses) * 8000;
    if (provider === "anthropic" && type.startsWith("web_fetch")) t += n(x.max_uses) * (Number(x.max_content_tokens) > 0 ? Math.ceil(Number(x.max_content_tokens)) : 25000);
    if (provider === "openai" && type.startsWith("web_search")) t += 10 * 8000;
  }
  return t;
}

// 本文に入っていない中身(サーバー側の会話・アップロード済みのファイル・URLの文書など)を参照している呼び出しか
function referencesOutside(provider: string, j: Record<string, any> | null): boolean {
  if (!j) return false;
  const s = JSON.stringify(j);
  if (provider === "openai") {
    if (j.previous_response_id || j.conversation || j.prompt?.id) return true;
    if (/"file_id"\s*:|"type"\s*:\s*"input_file"/.test(s)) return true;
    if (Array.isArray(j.tools) && j.tools.some((t: any) => t?.type === "mcp" || t?.type === "file_search")) return true;
  }
  if (provider === "anthropic") {
    if (j.mcp_servers || j.container) return true;
    if (/"source"\s*:\s*\{[^{}]*"type"\s*:\s*"(file|url)"/.test(s)) return true;
  }
  if (provider === "google") {
    if (j.cachedContent || /"fileData"|"file_data"|"fileUri"|"file_uri"/.test(s)) return true;
  }
  return false;
}
const pickKeys = (o: Record<string, any>, keys: string[]) => Object.fromEntries(keys.filter((k) => o[k] !== undefined).map((k) => [k, o[k]]));
// 入力のトークン数を、各社の「数えるだけ」の窓口(無料)で先に数える。数えられなければ -1
async function countInputTokens(provider: string, path: string, j: Record<string, any>, providerKey: string, req: Request): Promise<number> {
  try {
    const sig = AbortSignal.timeout(6000);
    if (provider === "anthropic" && /\/v1\/messages\/?$/.test(path)) {
      const h: Record<string, string> = { "content-type": "application/json", "x-api-key": providerKey, "anthropic-version": req.headers.get("anthropic-version") || "2023-06-01" };
      const beta = req.headers.get("anthropic-beta"); if (beta) h["anthropic-beta"] = beta;
      const r = await fetch(UPSTREAM.anthropic + "/v1/messages/count_tokens", { method: "POST", headers: h, signal: sig,
        body: JSON.stringify(pickKeys(j, ["model", "messages", "system", "tools", "tool_choice", "thinking", "mcp_servers"])) });
      const d = await r.json(); return r.ok && Number(d.input_tokens) > 0 ? Number(d.input_tokens) : -1;
    }
    if (provider === "openai" && /\/responses\/?$/.test(path)) {
      const r = await fetch(UPSTREAM.openai + "/v1/responses/input_tokens", { method: "POST", signal: sig,
        headers: { "content-type": "application/json", authorization: `Bearer ${providerKey}` },
        body: JSON.stringify(pickKeys(j, ["model", "input", "instructions", "previous_response_id", "conversation", "tools", "tool_choice", "reasoning", "text", "parallel_tool_calls", "truncation", "prompt"])) });
      const d = await r.json(); return r.ok && Number(d.input_tokens) > 0 ? Number(d.input_tokens) : -1;
    }
    const gm = path.match(/^(\/v1(?:beta)?)\/models\/([^/:]+):(?:stream)?generateContent/);
    if (provider === "google" && gm) {
      const r = await fetch(`${UPSTREAM.google}${gm[1]}/models/${gm[2]}:countTokens`, { method: "POST", signal: sig,
        headers: { "content-type": "application/json", "x-goog-api-key": providerKey },
        body: JSON.stringify({ generateContentRequest: { model: `models/${gm[2]}`, ...pickKeys(j, ["contents", "systemInstruction", "tools", "toolConfig", "cachedContent"]) } }) });
      const d = await r.json(); return r.ok && Number(d.totalTokens) > 0 ? Number(d.totalTokens) + (Number(d.cachedContentTokenCount) || 0) : -1;
    }
  } catch { /* 数えられなければ下の見積もり */ }
  return -1;
}

// Claude Code に「予算の75%・95%を使いました」と出してもらうための応答ヘッダー
// (Claude Code が支払い上限つきの中継から受け取る形と同じ。上流の同名ヘッダーは消して、このAIの予算の値だけを返す)
function limitHeaders(provider: string, gate: Record<string, any>): Record<string, string> {
  const util = Number(gate?.util), reset = Number(gate?.reset_epoch);
  if (provider !== "anthropic" || !Number.isFinite(util) || !Number.isFinite(reset)) return {};
  const th = util > 0.95 ? "0.95" : util > 0.75 ? "0.75" : "";
  const status = th ? "allowed_warning" : "allowed";
  const h: Record<string, string> = {
    "anthropic-ratelimit-unified-status": status,
    "anthropic-ratelimit-unified-representative-claim": "overage",
    "anthropic-ratelimit-unified-overage-status": status,
    "anthropic-ratelimit-unified-overage-utilization": util.toFixed(2),
    "anthropic-ratelimit-unified-reset": String(reset),
    "anthropic-ratelimit-unified-overage-reset": String(reset),
  };
  if (th) h["anthropic-ratelimit-unified-overage-surpassed-threshold"] = th;
  return h;
}
const stripUnified = (h: Headers) => { for (const k of [...h.keys()]) if (k.toLowerCase().startsWith("anthropic-ratelimit-unified-")) h.delete(k); };

function errorResponse(provider: string, status: number, type: string, message: string, lang?: string, extra: Record<string, string> = {}) {
  // 持ち主の言語が分かるときはその言語で、分からないときは日本語と英語の両方で返す
  const prefix = lang === "en" ? "[Saifuban]" : lang === "ja" ? "[AIの財布番]" : "[AIの財布番 / Saifuban]";
  const msg = `${prefix} ${message}`;
  const body = provider === "anthropic"
    ? { type: "error", error: { type, message: msg } }
    : provider === "google"
    ? { error: { code: status, status: type, message: msg } }
    : { error: { type, code: type, message: msg } };
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...(status === 429 ? { "Retry-After": "5" } : {}), ...extra },
  });
}

// レスポンスの中から利用量を拾う(Anthropic / OpenAI の各形式に対応、ストリームは最大値を採用)
function absorb(u: Usage, obj: unknown) {
  if (!obj || typeof obj !== "object") return;
  const o = obj as Record<string, any>;
  const model = o.model ?? o.message?.model ?? o.response?.model ?? o.modelVersion;
  if (typeof model === "string" && model) u.model = model;
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  u.outBytes += deltaBytes(o);
  // 最後の利用量が届いたか(Anthropic: message_delta / OpenAI: 利用量つきの最後のチャンク・response.completed / Google: finishReason)
  if (o.type === "message_delta" || o.type === "message_stop" || o.type === "response.completed" || o.type === "response.incomplete" ||
      (o.object === "chat.completion.chunk" && o.usage) || (Array.isArray(o.candidates) && o.candidates.some((c: any) => c?.finishReason))) u.final = true;
  // ウェブ検索などの回数
  const st = o.usage?.server_tool_use ?? o.message?.usage?.server_tool_use;
  if (st && typeof st === "object") u.searches = Math.max(u.searches, n(st.web_search_requests));
  const items: any[] = [...(Array.isArray(o.output) ? o.output : []), ...(Array.isArray(o.response?.output) ? o.response.output : []), ...(o.item ? [o.item] : [])];
  for (const it of items) {
    if (!it || typeof it !== "object" || typeof it.type !== "string") continue;
    const id = String(it.id ?? `${it.type}:${u.toolIds.size}`);
    if (u.toolIds.has(id)) continue;
    if (it.type === "web_search_call") { u.toolIds.add(id); u.searches++; }
    else if (it.type === "file_search_call") { u.toolIds.add(id); u.fileSearches++; }
  }
  for (const c of Array.isArray(o.candidates) ? o.candidates : []) {
    const gm = c?.groundingMetadata;
    if (gm && typeof gm === "object") {
      u.grounded = true;
      if (Array.isArray(gm.webSearchQueries)) u.groundedQueries = Math.max(u.groundedQueries, gm.webSearchQueries.filter((q: unknown) => typeof q === "string" && q.trim()).length);
    }
  }
  // Google 純正形式
  const g = o.usageMetadata;
  if (g && typeof g === "object") {
    u.seen = true;
    u.input = Math.max(u.input, n(g.promptTokenCount) - n(g.cachedContentTokenCount));
    u.cacheRead = Math.max(u.cacheRead, n(g.cachedContentTokenCount));
    u.output = Math.max(u.output, n(g.candidatesTokenCount) + n(g.thoughtsTokenCount));
  }
  for (const us of [o.usage, o.message?.usage, o.response?.usage]) {
    if (!us || typeof us !== "object") continue;
    u.seen = true;
    if (typeof us.cost === "number" && Number.isFinite(us.cost)) u.cost = Math.max(u.cost ?? 0, us.cost);
    u.input = Math.max(u.input, n(us.input_tokens) || n(us.prompt_tokens));
    u.output = Math.max(u.output, n(us.output_tokens) || n(us.completion_tokens));
    u.cacheWrite = Math.max(u.cacheWrite, n(us.cache_creation_input_tokens));
    u.cacheRead = Math.max(u.cacheRead, n(us.cache_read_input_tokens));
  }
}

// 予約(slot)ごとに1回だけ精算する。再送や取り消しが重なっても、データベース側で二重に計上しない
// 戻り値: "none" = 使っていない(0円で閉じてよい) / "done" = 精算した / "failed" = 失敗(予約は残し、10分後に予約額で計上される)
async function settle(slot: unknown, provider: string, u: Usage, basis: "usage" | "cancelled" = "usage"): Promise<"none" | "done" | "failed"> {
  if (slot == null) return "none";
  const extra = basis === "usage" ? extraUsd(provider, u) : 0;
  if (!u.seen || ((u.input + u.output + u.cacheWrite + u.cacheRead) === 0 && !u.cost && !extra)) return "none";
  const { error } = await db.rpc("sb_proxy_settle", {
    p_slot: slot, p_provider: provider, p_model: u.model,
    p_in: u.input, p_out: u.output, p_cache_write: u.cacheWrite, p_cache_read: u.cacheRead,
    p_cost_usd: u.cost, p_basis: basis, p_extra_usd: extra,
    p_extra_note: extra ? [u.searches && `search ×${u.searches}`, u.fileSearches && `file search ×${u.fileSearches}`, u.groundedQueries && `grounding ×${u.groundedQueries}`].filter(Boolean).join(", ") || "grounding" : null,
  });
  if (error) { console.error("settle", error); return "failed"; }
  return "done";
}

// 同時に流せる枠を返す(何度呼んでも1回だけ)
function releaser(slot: unknown) {
  let done = false;
  return async () => {
    if (done || slot == null) return;
    done = true;
    const { error } = await db.rpc("sb_proxy_release", { p_slot: slot });
    if (error) console.error("release", error);
  };
}

// 応答の本文(SSE か JSON)から利用量を拾う
function absorbText(u: Usage, text: string, isSse: boolean) {
  if (isSse) {
    for (const line of text.split("\n")) {
      const t = line.trim();
      if (!t.startsWith("data:")) continue;
      const d = t.slice(5).trim();
      if (!d || d === "[DONE]") continue;
      try { absorb(u, JSON.parse(d)); } catch { /* 途中の行は無視 */ }
    }
  } else {
    try { const p = JSON.parse(text); for (const item of Array.isArray(p) ? p : [p]) absorb(u, item); } catch { /* JSON以外 */ }
  }
}

// Worker との合言葉(データベースの保管庫にある。初回だけ読み出して覚えておく)
let RELAY_SECRET = Deno.env.get("SAIFUBAN_RELAY_SECRET") || "";
async function relayOk(req: Request) {
  if (!RELAY_SECRET) {
    const { data } = await db.rpc("sb_relay_secret");
    RELAY_SECRET = typeof data === "string" ? data : "";
  }
  const got = req.headers.get("x-saifuban-relay") || "";
  if (RELAY_SECRET.length < 32 || got.length !== RELAY_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ RELAY_SECRET.charCodeAt(i);
  return diff === 0;
}

// Worker から届いた応答で精算する
async function relaySettle(req: Request, url: URL) {
  const slot = Number(url.searchParams.get("slot"));
  if (!Number.isFinite(slot) || slot <= 0) return new Response(JSON.stringify({ error: "bad_slot" }), { status: 400 });
  const { data: row } = await db.from("proxy_inflight").select("provider, model, est_usd, est_in, is_generation, settled_at").eq("id", slot).maybeSingle();
  if (!row) return new Response(JSON.stringify({ error: "unknown_slot" }), { status: 404 });
  const provider = String(row.provider || "");
  const status = Number(url.searchParams.get("status") || "0");
  const normalEnd = url.searchParams.get("normal") === "1";
  const isSse = url.searchParams.get("sse") === "1";
  const text = new TextDecoder().decode(await req.arrayBuffer());
  const estimate = (why: string): Usage => ({ ...newUsage(`${row.model || "unknown"} (estimate: ${why})`), cost: Number(row.est_usd), seen: true });
  let r: "none" | "done" | "failed" = "none";
  if (status === 0) {
    r = "none"; // APIに届かなかった
  } else if (status >= 200 && status < 300) {
    const usage = newUsage(String(row.model || ""));
    absorbText(usage, text, isSse);
    if (!isSse) usage.final = true;
    const complete = usage.final || (normalEnd && usage.seen && usage.output > 0);
    const cut = row.is_generation && !complete && row.est_usd != null;
    r = await (cut
      ? settle(slot, provider, await cutUsage(provider, String(usage.model || row.model || ""), usage, Number(row.est_in) || 0, Number(row.est_usd)), "cancelled")
      : settle(slot, provider, usage));
  } else if (!normalEnd && row.is_generation && row.est_usd != null) {
    r = await settle(slot, provider, estimate("relay error"), "cancelled");
  }
  if (r === "none") await releaser(slot)();
  return new Response(JSON.stringify({ ok: r !== "failed", result: r }), { status: r === "failed" ? 500 : 200, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  // Worker(長い応答用の中継)からの呼び出し
  const relay = url.pathname.match(/\/saifuban-proxy\/_relay\/(gate|settle)(\/.*)?$/);
  if (relay) {
    if (!(await relayOk(req))) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403, headers: { "Content-Type": "application/json" } });
    if (relay[1] === "settle") return await relaySettle(req, url);
  }
  const gateMode = !!relay;
  const m = (gateMode ? (relay![2] || "") : url.pathname).match(gateMode ? /^\/(anthropic|openai|google|openrouter)(\/.*)?$/ : /\/saifuban-proxy\/(anthropic|openai|google|openrouter)(\/.*)?$/);
  if (!m) {
    return new Response(JSON.stringify({ error: "use /saifuban-proxy/{anthropic|openai|google|openrouter}/..." }), {
      status: 404, headers: { "Content-Type": "application/json" },
    });
  }
  const provider = m[1];
  const path = m[2] || "/";

  // 本物のキーと財布番のキーが両方付いてくることがある(Claude Code で ANTHROPIC_API_KEY と ANTHROPIC_AUTH_TOKEN が両方あるときなど)。
  // sbk_ で始まる方を使う
  const cands = [req.headers.get("x-api-key"), req.headers.get("x-goog-api-key"),
    req.headers.get("authorization")?.replace(/^Bearer\s+/i, ""), url.searchParams.get("key")].map((v) => (v || "").trim()).filter(Boolean);
  const key = cands.find((v) => v.startsWith("sbk_")) || cands[0] || "";
  url.searchParams.delete("key"); // エージェントキーを外部に渡さない
  if (!key.startsWith("sbk_")) {
    return errorResponse(provider, 401, "authentication_error", "財布番のエージェントキー(sbk_...)をAPIキーとして設定してください / Set your Saifuban agent key (sbk_...) as the API key");
  }

  // 先に本文を読み、モデル名・入力の大きさ・出力の上限から「かかりうる最大額」を見積もる
  const method = gateMode ? (req.headers.get("x-saifuban-method") || "GET").toUpperCase() : req.method;
  let raw: ArrayBuffer | null = null;
  let parsed: Record<string, any> | null = null;
  if (!["GET", "HEAD"].includes(method)) {
    raw = await req.arrayBuffer();
    if ((req.headers.get("content-type") || "").includes("application/json") && raw.byteLength) {
      try { const j = JSON.parse(new TextDecoder().decode(raw)); if (j && typeof j === "object" && !Array.isArray(j)) parsed = j; } catch { /* JSONでなければそのまま送る */ }
    }
  }
  const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.ceil(v) : 0);
  const pathModel = path.match(/models\/([^/:]+)/)?.[1] ?? "";
  const estModel = (typeof parsed?.model === "string" ? parsed.model : "") || pathModel;
  // 予算で数えられない(あとでまとめて請求される・トークン以外で請求される)呼び出しは通さない。通すと上限を素通りできてしまう
  if (method === "POST" && /\/batches|batchGenerateContent|asyncBatchEmbedContent|\/images\/|\/audio\/|\/videos|\/fine_tuning|\/realtime|:predict|predictLongRunning/.test(path)) {
    return errorResponse(provider, 403, "permission_error", "財布番はこの種類の呼び出し(バッチ・画像・音声・動画・ファインチューニング等)の金額を数えられないため、通しません / Saifuban can't meter this endpoint (batches, images, audio, video, fine-tuning, realtime), so it is blocked to keep the budget safe");
  }
  // トークン数を数えるだけの呼び出しは無料。予約も上限の書き込みもしない(書き込むと 400 になる)
  const isCountOnly = /count_tokens|input_tokens|countTokens/.test(path);
  const isGeneration = method === "POST" && !isCountOnly && /messages|completions|responses|generateContent|embeddings|embedContent/.test(path);
  // 入力は本文の大きさから多めに見積もる(3バイト=1トークン)。出力は指定された上限。
  // 指定がなければ -1 を渡し、財布番が「モデルの最大と32,768の小さい方」を上限に決めて、リクエストに書き込む
  // (予約より長く書かれて上限を超えることがないように)
  let estIn = raw ? Math.ceil(raw.byteLength / 3) : 0;
  const givenOut = num(parsed?.max_tokens) || num(parsed?.max_completion_tokens) || num(parsed?.max_output_tokens) ||
    num(parsed?.generationConfig?.maxOutputTokens);
  const estOut = !isGeneration || /embeddings|embedContent/.test(path) ? 0 : (givenOut || (parsed ? -1 : 16384));
  // 1回で複数の答えを作らせる指定(n / candidateCount)は、その数だけ出力が増える
  const choices = Math.max(1, Math.min(16, num(parsed?.n) || num(parsed?.generationConfig?.candidateCount) || 1));
  // 予算の残りが足りないときは、出力の上限を縮めて通す。ただし最低 4,096 トークン(考える量の指定があればそれ+1,024)は書けるときだけ
  const thinkBudget = num(parsed?.thinking?.budget_tokens) || num(parsed?.generationConfig?.thinkingConfig?.thinkingBudget);
  const minOut = parsed && isGeneration && !/embeddings|embedContent/.test(path) ? Math.max(4096, thinkBudget ? thinkBudget + 1024 : 0) : 0;

  if (isGeneration) {
    // 検索・取得の結果として足される入力も見込む
    estIn += toolInputTokens(provider, parsed);
    // 本文の外にある中身を参照しているときは、入力を先に数えてから予約する(数えられなければ 32,000 トークンとみなす)
    if (referencesOutside(provider, parsed)) {
      const pre = await db.rpc("sb_proxy_begin", { p_key: key, p_provider: provider });
      const pk = pre.data && !pre.data.error ? String(pre.data.provider_key || "") : "";
      if (pk) {
        const counted = await countInputTokens(provider, path, parsed!, pk, req);
        estIn = Math.max(estIn, counted > 0 ? counted + toolInputTokens(provider, parsed) : 32000);
      }
    }
  }
  const { data: gate, error: gateErr } = await db.rpc("sb_proxy_begin_v5", {
    p_key: key, p_provider: provider, p_model: estModel, p_in_est: estIn, p_out_max: estOut,
    p_extra_usd: isGeneration ? extraEstimateUsd(provider, estModel, parsed) : 0, p_choices: choices, p_min_out: minOut,
  });
  if (gateErr || !gate) {
    console.error("begin", gateErr);
    return errorResponse(provider, 500, "api_error", "財布番の確認に失敗しました。時間をおいて再度お試しください / Saifuban check failed. Please try again later");
  }
  if (gate.error === "invalid_agent_key") return errorResponse(provider, 401, "authentication_error", "エージェントキーが正しくありません / Invalid agent key");
  // 予算切れ: Claude Code などがやり直さないよう x-should-retry: false を付け、リセットまでの秒数を Retry-After に入れる
  if (gate.error && gate.kind === "budget") {
    const secs = Math.max(60, Math.ceil((Date.parse(gate.reset_at) - Date.now()) / 1000) || 3600);
    const resetEpoch = String(Math.floor(Date.parse(gate.reset_at) / 1000) || "");
    return errorResponse(provider, 429, provider === "anthropic" ? "billing_error" : "insufficient_quota", gate.reason, gate.lang, {
      "Retry-After": String(secs), "x-should-retry": "false", "x-saifuban-reset-at": String(gate.reset_at),
      // 予算切れ: Claude Code はこのヘッダーを見て「上限に達した」と扱い、メッセージをそのまま表示する
      ...(provider === "anthropic" ? {
        "anthropic-ratelimit-unified-status": "rejected", "anthropic-ratelimit-unified-reset": resetEpoch,
        "anthropic-ratelimit-unified-overage-reset": resetEpoch, "anthropic-ratelimit-unified-overage-utilization": "1",
        "anthropic-ratelimit-unified-overage-surpassed-threshold": "1", "anthropic-ratelimit-unified-overage-period": String(gate.period || "daily"),
        "anthropic-ratelimit-unified-overage-disabled-reason": "org_spend_cap_reached",
      } : {}),
    });
  }
  if (gate.error && gate.status === 429) return errorResponse(provider, 429, "rate_limit_error", gate.reason, gate.lang);
  if (gate.error) return errorResponse(provider, 403, "permission_error", gate.reason || gate.error, gate.lang);
  const release = releaser(gate.slot);
  // 精算に使う見積もり(Worker 経由のときは、あとで別の呼び出しで精算するので保存しておく)
  await db.from("proxy_inflight").update({ est_usd: gate.estimate_usd ?? null, est_in: estIn, is_generation: isGeneration }).eq("id", gate.slot);
  let contacted = false; // APIにリクエストが届いたか(届いた後の失敗は、0円にせず予約額で計上する)
  const estimate = (why: string): Usage => ({ ...newUsage(`${estModel || "unknown"} (estimate: ${why})`), cost: gate.estimate_usd, seen: true });
  // この中継は1回の処理に時間の上限がある(無料プランは150秒)。上限の少し前に、いったん見積もり額で精算しておく。
  // 応答が最後まで届けば、そのとき実際の額に直す(データベース側で書き直す)。
  const LIMIT_MS = Number(Deno.env.get("SAIFUBAN_WALL_MS") || "150000") - 12000;
  const early = !gateMode && isGeneration && typeof gate.estimate_usd === "number"
    ? setTimeout(() => { settle(gate.slot, provider, estimate("time limit"), "cancelled").catch(() => {}); }, LIMIT_MS)
    : undefined;

  try {
    // リクエストを組み立て直す(本物のキーに差し替え)
    const headers = new Headers();
    for (const [k, v] of req.headers) {
      const lk = k.toLowerCase();
      if (["host", "authorization", "x-api-key", "content-length", "connection", "accept-encoding", "x-forwarded-for", "x-forwarded-host", "x-forwarded-proto", "x-real-ip", "cf-connecting-ip", "x-client-info", "apikey", "x-goog-api-key"].includes(lk)) continue;
      if (lk.startsWith("sb-") || lk.startsWith("x-supabase") || lk.startsWith("x-saifuban") || lk.startsWith("cf-")) continue;
      headers.set(k, v);
    }
    if (provider === "anthropic") headers.set("x-api-key", gate.provider_key);
    else if (provider === "google" && !path.includes("/openai/")) headers.set("x-goog-api-key", gate.provider_key);
    else headers.set("authorization", `Bearer ${gate.provider_key}`);

    let body: BodyInit | null = raw;
    const requestModel = typeof parsed?.model === "string" ? parsed.model : "";
    if (parsed) {
      const j = parsed;
      // OpenAI のストリームで利用量を受け取るための設定
      let changed = false;
      if (provider !== "anthropic" && j.stream === true && path.includes("/chat/completions")) {
        j.stream_options = { ...(j.stream_options || {}), include_usage: true };
        changed = true;
      }
      // 出力の上限が指定されていなければ、予約した上限を書き込む(それ以上は書かせない)
      // 予算に合わせて縮めたとき(shrunk_from)は、指定されていた上限も書き換える
      const cap = Number(gate.out_max);
      if (cap > 0 && (!givenOut || gate.shrunk_from)) {
        let set = false;
        if (num(j.max_tokens)) { j.max_tokens = cap; set = true; }
        if (num(j.max_completion_tokens)) { j.max_completion_tokens = cap; set = true; }
        if (num(j.max_output_tokens)) { j.max_output_tokens = cap; set = true; }
        if (num(j.generationConfig?.maxOutputTokens)) { j.generationConfig.maxOutputTokens = cap; set = true; }
        if (!set) {
          if (provider === "google" && /generateContent/.test(path)) j.generationConfig = { ...(j.generationConfig || {}), maxOutputTokens: cap };
          else if (/\/responses/.test(path)) j.max_output_tokens = cap;
          else if (provider === "openai") j.max_completion_tokens = cap;
          else j.max_tokens = cap;
        }
        changed = true;
      }
      // OpenRouter は実際にかかった金額(USD)を返してもらう
      if (provider === "openrouter") {
        j.usage = { ...(typeof j.usage === "object" ? j.usage : {}), include: true };
        changed = true;
      }
      if (changed) body = JSON.stringify(j);
    }

    if (gateMode) {
      // Worker に「送り先・ヘッダー(本物のキー入り)・本文(書き換えたときだけ)」を渡す。送受信は Worker が行う
      const changedBody = typeof body === "string" ? body : null;
      const target = new URL(UPSTREAM[provider] + path + url.search);
      target.searchParams.delete("key");
      return new Response(JSON.stringify({
        ok: true, slot: gate.slot, url: target.toString(), method,
        headers: Object.fromEntries(headers.entries()), body: changedBody, remaining_jpy: gate.remaining_jpy,
        capped: gate.shrunk_from ? `${gate.shrunk_from}->${gate.out_max}` : null,
        out_headers: limitHeaders(provider, gate),
      }), { status: 200, headers: { "Content-Type": "application/json", "x-saifuban-gate": "ok", "Cache-Control": "no-store" } });
    }

    let upstream: Response;
    try {
      upstream = await fetch(UPSTREAM[provider] + path + url.search, { method: req.method, headers, body });
    } catch (e) {
      console.error("upstream", e);
      await release();
      return errorResponse(provider, 502, "api_error", gate.lang === "en" ? "Could not reach the API" : "APIに接続できませんでした", gate.lang);
    }

    contacted = true;
    const outHeaders = new Headers(upstream.headers);
    outHeaders.delete("content-encoding");
    outHeaders.delete("content-length");
    outHeaders.set("x-saifuban-remaining-jpy", String(gate.remaining_jpy));
    if (gate.shrunk_from) outHeaders.set("x-saifuban-output-capped", `${gate.shrunk_from}->${gate.out_max}`);
    stripUnified(outHeaders);
    if (upstream.ok) for (const [k, v] of Object.entries(limitHeaders(provider, gate))) outHeaders.set(k, v);

    const usage: Usage = newUsage(requestModel || (path.match(/models\/([^/:]+)/)?.[1] ?? ""));
    const ctype = upstream.headers.get("content-type") || "";

    if (upstream.ok && upstream.body && ctype.includes("text/event-stream")) {
      const decoder = new TextDecoder();
      let buf = "";
      const scan = (line: string) => {
        const t = line.trim();
        if (!t.startsWith("data:")) return;
        const d = t.slice(5).trim();
        if (!d || d === "[DONE]") return;
        try { absorb(usage, JSON.parse(d)); } catch { /* 途中の行は無視 */ }
      };
      const tap = new TransformStream<Uint8Array, Uint8Array>({
        transform(chunk, ctrl) {
          ctrl.enqueue(chunk);
          buf += decoder.decode(chunk, { stream: true });
          let i;
          while ((i = buf.indexOf("\n")) >= 0) { scan(buf.slice(0, i)); buf = buf.slice(i + 1); }
        },
        flush() {
          if (buf) scan(buf);
        },
      });
      // 精算と枠の返却は1回だけ。途中で切られた場合も行う(精算が届かなければ10分後に予約額で計上される)
      let finished = false;
      const finish = async (normalEnd: boolean) => {
        if (finished) return;
        finished = true;
        clearTimeout(early);
        // 最後の利用量が届く前に切れた場合(途中で取り消された・接続が切れた)は、少なく記録しないよう見積もり額で記録する
        // (最後まで正常に流れ終わり、出力トークン数が分かっている場合は、その数で精算する)
        const complete = usage.final || (normalEnd && usage.seen && usage.output > 0);
        const cut = isGeneration && !complete && typeof gate.estimate_usd === "number";
        const r = await (cut ? settle(gate.slot, provider, await cutUsage(provider, usage.model || estModel, usage, estIn, gate.estimate_usd), "cancelled") : settle(gate.slot, provider, usage))
          .catch((e) => { console.error("settle", e); return "failed" as const; });
        if (r === "none") await release(); // 利用がなかったときだけ0円で閉じる
      };
      const piped = upstream.body.pipeThrough(tap);
      const reader = piped.getReader();
      const guarded = new ReadableStream<Uint8Array>({
        async pull(ctrl) {
          try {
            const { done, value } = await reader.read();
            if (done) { ctrl.close(); await finish(true); return; }
            ctrl.enqueue(value);
          } catch (e) {
            ctrl.error(e);
            await finish(false);
          }
        },
        async cancel() {
          reader.cancel().catch(() => {});
          await finish(false);
        },
      });
      return new Response(guarded, { status: upstream.status, headers: outHeaders });
    }

    const text = await upstream.text();
    clearTimeout(early);
    if (upstream.ok) {
      try {
        const parsed = JSON.parse(text);
        // Google のストリーム(alt=sse なし)は配列で返る
        for (const item of Array.isArray(parsed) ? parsed : [parsed]) absorb(usage, item);
      } catch { /* JSON以外 */ }
      usage.final = true;
      if ((await settle(gate.slot, provider, usage)) !== "none") return new Response(text, { status: upstream.status, headers: outHeaders });
    }
    await release();
    return new Response(text, { status: upstream.status, headers: outHeaders });
  } catch (e) {
    console.error("proxy", e);
    clearTimeout(early);
    if (contacted && isGeneration && typeof gate.estimate_usd === "number") {
      await settle(gate.slot, provider, estimate("proxy error"), "cancelled").catch(() => {});
    } else await release();
    return errorResponse(provider, 500, "api_error", gate.lang === "en" ? "Proxy error" : "中継でエラーが起きました", gate.lang);
  }
});
