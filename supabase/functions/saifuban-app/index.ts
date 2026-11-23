// AIの財布番 — サイト(持ち主の画面)用のAPI
// 認証: x-owner-key: sbo_...(アカウントの合言葉)。キーはDB側でSHA-256照合。
// POST /saifuban-app  { action: "...", ...引数 }
// GET  /saifuban-app/vapid   通知の公開鍵
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { pushServer, sendPush } from "./push.ts";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, x-owner-key",
  "Access-Control-Max-Age": "86400",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" } });

const str = (v: unknown, max = 500) => (typeof v === "string" ? v.slice(0, max) : "");
const int = (v: unknown) => {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? Math.max(0, Math.min(100_000_000, n)) : 0;
};
const list = (v: unknown) => (Array.isArray(v) ? v.filter((x) => typeof x === "string").slice(0, 50).map((x) => x.slice(0, 200)) : []);
const uuid = (v: unknown) => (typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v) ? v : "00000000-0000-0000-0000-000000000000");

async function call(fn: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(fn, args);
  if (error) {
    console.error(fn, error);
    return json({ error: "server_error" }, 500);
  }
  if (data && typeof data === "object" && "error" in data) {
    return json(data, data.error === "invalid_owner_key" ? 401 : 400);
  }
  return json(data);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const url = new URL(req.url);

  try {
    if (req.method === "GET" && url.pathname.endsWith("/vapid")) {
      const { pub } = await pushServer(db);
      return json({ public_key: pub });
    }
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

    let b: Record<string, unknown> = {};
    try { b = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
    const action = str(b.action, 40);
    if (action === "signup") return await call("app_signup", {});
    // サイトの訪問数など(個人を特定しない日別の件数だけ)
    if (action === "track") return await call("app_track", { p_event: str(b.event, 20), p_src: str(b.src, 80), p_lang: str(b.lang, 5) });

    // コネクタの許可画面(OAuth)。合言葉がなくても内容の表示と「拒否」はできる
    if (action === "oauth_info") return await call("app_oauth_info", { p_owner_key: req.headers.get("x-owner-key") || "", p_req: str(b.req, 64) });
    if (action === "oauth_decide") {
      const aid = typeof b.agent_id === "string" && /^[0-9a-f-]{36}$/i.test(b.agent_id) ? b.agent_id : null;
      return await call("app_oauth_decide", { p_owner_key: req.headers.get("x-owner-key") || "", p_req: str(b.req, 64), p_agent: aid,
        p_new_name: str(b.name, 60), p_daily: int(b.daily), p_auto: int(b.auto), p_approve: b.approve === true });
    }

    // GitHub・Google でログイン: Supabase のログインで本人を確かめ、つながっている財布番のアカウントに入る(なければ作る)
    if (action === "social_login") return await socialLogin(str(b.access_token, 4000));

    const key = req.headers.get("x-owner-key") || "";
    if (!/^sbo_[0-9a-f]{48}$/.test(key)) return json({ error: "invalid_owner_key" }, 401);
    const K = { p_owner_key: key };

    switch (action) {
      case "dashboard": {
        const [d, p] = await Promise.all([db.rpc("app_dashboard", K), db.rpc("app_owner_prefs", K)]);
        if (d.error) { console.error("app_dashboard", d.error); return json({ error: "server_error" }, 500); }
        if (d.data && d.data.error) return json(d.data, d.data.error === "invalid_owner_key" ? 401 : 400);
        return json({ ...d.data, currency: p.data?.currency ?? "JPY", lang: p.data?.lang ?? "ja" });
      }
      case "set_currency":
        return await call("app_set_currency", { ...K, p_currency: b.currency === "USD" ? "USD" : "JPY" });
      case "create_agent":
        return await call("app_create_agent", { ...K, p_name: str(b.name, 60), p_per_tx: int(b.per_tx), p_daily: int(b.daily), p_auto: int(b.auto), p_merchants: list(b.merchants) });
      case "update_agent": {
        const base = { ...K, p_id: uuid(b.id), p_name: str(b.name, 60), p_per_tx: int(b.per_tx), p_daily: int(b.daily), p_auto: int(b.auto), p_merchants: list(b.merchants), p_active: b.active !== false };
        // 週・月の上限、「初めての支払先は確認」、同時に流せる数は送られてきたときだけ変える(空欄・0 = 上限なし)
        if (!["weekly", "monthly", "known_only", "max_concurrent"].some((f) => f in b)) return await call("app_update_agent", base);
        const opt = (v: unknown) => (v == null || v === "" ? null : int(v) || null);
        return await call("app_update_agent_v4", { ...base, p_weekly: opt(b.weekly), p_monthly: opt(b.monthly),
          p_known_only: "known_only" in b ? b.known_only === true : null,
          p_max_concurrent: "max_concurrent" in b ? opt(b.max_concurrent) : null });
      }
      case "delete_agent":
        return await call("app_archive_agent", { ...K, p_id: uuid(b.id) });
      case "rotate_key":
        return await call("app_rotate_key", { ...K, p_id: uuid(b.id) });
      case "decide":
        return await call("app_decide", { ...K, p_id: Math.max(0, Math.round(Number(b.id) || 0)), p_approve: b.approve === true });
      case "set_kill":
        return await call("app_set_kill", { ...K, p_kill: b.kill === true });
      case "set_ntfy":
        return await call("app_set_ntfy", { ...K, p_topic: typeof b.topic === "string" ? b.topic : null });
      case "set_lang":
        return await call("app_set_lang", { ...K, p_lang: b.lang === "en" ? "en" : "ja" });
      // 1日・週・月の区切りに使う時間帯(auto=true は、まだ一度も決めていないときだけ変わる)
      case "set_tz":
        return await call("app_set_tz", { ...K, p_tz: str(b.tz, 64), p_auto: b.auto === true });
      case "set_provider_key":
        return await call("app_set_provider_key", { ...K, p_provider: str(b.provider, 20), p_key: str(b.key, 400) });
      case "push_subscribe": {
        const s = (b.subscription ?? {}) as Record<string, any>;
        return await call("app_push_subscribe", { ...K, p_endpoint: str(s.endpoint, 1000), p_p256dh: str(s.keys?.p256dh, 200), p_auth: str(s.keys?.auth, 100) });
      }
      case "push_unsubscribe":
        return await call("app_push_unsubscribe", { ...K, p_endpoint: str(b.endpoint, 1000) });
      case "push_test": {
        const { data: d } = await db.rpc("app_dashboard", K);
        if (!d || d.error) return json({ error: "invalid_owner_key" }, 401);
        const { data: owner } = await db.from("owners").select("id").eq("key_hash", await sha256(key)).single();
        const { data: targets } = await db.rpc("sb_push_targets", { p_owner: owner?.id });
        const { data: lang } = await db.rpc("sb_owner_lang", { p_owner: owner?.id });
        const en = lang === "en";
        const r = await sendPush(db, targets ?? [], en
          ? { type: "test", lang: "en", title: "Saifuban", body: "Notifications are set up. Payments that need your approval will show up here." }
          : { type: "test", lang: "ja", title: "AIの財布番", body: "通知の設定ができました。承認待ちが出たらここに届きます。" });
        return json({ ok: true, ...r });
      }
      // ログイン中のアカウントに GitHub・Google をつなぐ(次から合言葉なしで入れる)
      case "social_link": return await socialLink(key, str(b.access_token, 4000));
      case "identities": return await call("app_identities", K);
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    console.error(e);
    return json({ error: "server_error" }, 500);
  }
});

async function sha256(s: string) {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  return Array.from(h, (x) => x.toString(16).padStart(2, "0")).join("");
}

// Supabase のログイン(GitHub・Google)を確かめて、本人の情報を返す。確かめたらその場でログアウトさせる(財布番は合言葉で動くため)
async function authUser(token: string) {
  if (!token) return null;
  const { data, error } = await db.auth.getUser(token);
  if (error || !data?.user) return null;
  const u = data.user;
  const provider = String(u.app_metadata?.provider || (u.identities?.[0]?.provider ?? "unknown"));
  try { await db.auth.admin.signOut(token); } catch { /* 期限切れなどは気にしない */ }
  return { id: u.id, provider, email: u.email ?? null };
}
// この端末用の合言葉を発行する(パスキーでログインしたときと同じ)
async function deviceKey(owner: string, note: string) {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  const k = "sbo_" + Array.from(bytes, (x) => x.toString(16).padStart(2, "0")).join("");
  const { error } = await db.from("owner_device_keys").insert({ key_hash: await sha256(k), owner_id: owner, key_hint: k.slice(0, 10) + "…" + note });
  return error ? null : k;
}
async function socialLogin(token: string) {
  const u = await authUser(token);
  if (!u) return json({ error: "not_signed_in" }, 401);
  const { data: idn } = await db.from("owner_identities").select("owner_id").eq("auth_user", u.id).maybeSingle();
  if (idn) {
    await db.from("owner_identities").update({ last_login_at: new Date().toISOString() }).eq("auth_user", u.id);
    const k = await deviceKey(idn.owner_id, ` (${u.provider})`);
    return k ? json({ ok: true, owner_key: k, created: false, provider: u.provider }) : json({ error: "server_error" }, 500);
  }
  // 初めて: アカウントを作ってつなぐ
  const { data: su, error } = await db.rpc("app_signup", {});
  if (error || !su?.owner_key) return json({ error: "server_error" }, 500);
  const { data: o } = await db.rpc("app_owner", { p_key: su.owner_key });
  const ins = await db.from("owner_identities").insert({ auth_user: u.id, owner_id: o?.id, provider: u.provider, email: u.email, last_login_at: new Date().toISOString() });
  if (ins.error) return json({ error: "server_error" }, 500);
  return json({ ok: true, owner_key: su.owner_key, created: true, provider: u.provider });
}
async function socialLink(ownerKey: string, token: string) {
  const { data: o } = await db.rpc("app_owner", { p_key: ownerKey });
  if (!o?.id) return json({ error: "invalid_owner_key" }, 401);
  const u = await authUser(token);
  if (!u) return json({ error: "not_signed_in" }, 401);
  const { data: idn } = await db.from("owner_identities").select("owner_id").eq("auth_user", u.id).maybeSingle();
  if (idn && idn.owner_id !== o.id) return json({ error: "already_linked" }, 409);
  if (!idn) {
    const ins = await db.from("owner_identities").insert({ auth_user: u.id, owner_id: o.id, provider: u.provider, email: u.email });
    if (ins.error) return json({ error: "server_error" }, 500);
  }
  return json({ ok: true, provider: u.provider });
}
