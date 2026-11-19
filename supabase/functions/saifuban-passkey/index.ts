// AIの財布番 — パスキーでログイン(顔・指紋・端末のロック)
// 登録: 合言葉でログイン中の端末から、パスキーを作って保存する
// ログイン: パスキーで本人確認できたら、その端末用の合言葉(sbo_…)を新しく発行して返す
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "npm:@simplewebauthn/server@10.0.1";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

// 受け付ける画面の住所と、それに対応するパスキーの持ち主(rpID)
const ORIGINS: Record<string, string> = {
  "https://ut181749ut.github.io": "ut181749ut.github.io",
  "http://localhost:8766": "localhost",
};
// セルフホスト: 自分の画面の住所を SAIFUBAN_SITE_URL に入れると、そこでもパスキーが使える
{
  const site = Deno.env.get("SAIFUBAN_SITE_URL");
  if (site) { const u = new URL(site); ORIGINS[u.origin] = u.hostname; }
}

const cors = (origin: string) => ({
  "Access-Control-Allow-Origin": ORIGINS[origin] ? origin : "https://ut181749ut.github.io",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, x-owner-key",
  "Vary": "Origin",
});

const b64u = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const fromB64u = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));
async function sha256hex(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function ownerOf(key: string | null) {
  if (!key || !key.startsWith("sbo_")) return null;
  const { data } = await db.rpc("app_owner", { p_key: key });
  return data && data.id ? data : null;
}

async function takeChallenge(id: string, kind: string) {
  const { data } = await db.from("passkey_challenges").delete().eq("id", id).eq("kind", kind)
    .gt("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString()).select().maybeSingle();
  return data;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") || "";
  const H = { ...cors(origin), "Content-Type": "application/json" };
  const J = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: H });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(origin) });
  if (req.method !== "POST") return J({ error: "method_not_allowed" }, 405);
  const rpID = ORIGINS[origin];
  if (!rpID) return J({ error: "bad_origin" }, 403);
  let body: any = {};
  try { body = await req.json(); } catch { return J({ error: "bad_request" }, 400); }

  try {
    // 古い確認用の文字列を片付ける
    await db.from("passkey_challenges").delete().lt("created_at", new Date(Date.now() - 10 * 60 * 1000).toISOString());

    if (body.action === "reg_options") {
      const owner = await ownerOf(req.headers.get("x-owner-key"));
      if (!owner) return J({ error: "invalid_owner_key" }, 401);
      const { data: existing } = await db.from("owner_passkeys").select("credential_id, transports").eq("owner_id", owner.id).eq("rp_id", rpID);
      const opts = await generateRegistrationOptions({
        rpName: "Saifuban",
        rpID,
        userID: new TextEncoder().encode(owner.id),
        userName: "Saifuban " + (owner.key_hint || "").replace("…", ""),
        userDisplayName: "AIの財布番 / Saifuban",
        attestationType: "none",
        authenticatorSelection: { residentKey: "required", userVerification: "preferred" },
        excludeCredentials: (existing || []).map((c: any) => ({ id: c.credential_id, transports: c.transports || undefined })),
      });
      const { data: ch } = await db.from("passkey_challenges").insert({ challenge: opts.challenge, owner_id: owner.id, kind: "reg", rp_id: rpID }).select("id").single();
      return J({ ok: true, challenge_id: ch!.id, options: opts });
    }

    if (body.action === "reg_verify") {
      const owner = await ownerOf(req.headers.get("x-owner-key"));
      if (!owner) return J({ error: "invalid_owner_key" }, 401);
      const ch = await takeChallenge(String(body.challenge_id || ""), "reg");
      if (!ch || ch.owner_id !== owner.id || ch.rp_id !== rpID) return J({ error: "challenge_expired" }, 400);
      const v = await verifyRegistrationResponse({
        response: body.response, expectedChallenge: ch.challenge, expectedOrigin: origin, expectedRPID: rpID, requireUserVerification: false,
      });
      if (!v.verified || !v.registrationInfo) return J({ error: "not_verified" }, 400);
      const info: any = v.registrationInfo;
      const credId: string = info.credential?.id ?? (typeof info.credentialID === "string" ? info.credentialID : b64u(info.credentialID));
      const pub: Uint8Array = info.credential?.publicKey ?? info.credentialPublicKey;
      const counter: number = info.credential?.counter ?? info.counter ?? 0;
      const { error } = await db.from("owner_passkeys").insert({
        owner_id: owner.id, credential_id: credId, public_key: b64u(pub), counter,
        transports: Array.isArray(body.response?.response?.transports) ? body.response.response.transports.slice(0, 6) : null, rp_id: rpID,
      });
      if (error) return J({ error: "save_failed" }, 500);
      return J({ ok: true });
    }

    if (body.action === "auth_options") {
      const opts = await generateAuthenticationOptions({ rpID, userVerification: "preferred" });
      const { data: ch } = await db.from("passkey_challenges").insert({ challenge: opts.challenge, kind: "auth", rp_id: rpID }).select("id").single();
      return J({ ok: true, challenge_id: ch!.id, options: opts });
    }

    if (body.action === "auth_verify") {
      const ch = await takeChallenge(String(body.challenge_id || ""), "auth");
      if (!ch || ch.rp_id !== rpID) return J({ error: "challenge_expired" }, 400);
      const credId = String(body.response?.id || "");
      const { data: cred } = await db.from("owner_passkeys").select("*").eq("credential_id", credId).eq("rp_id", rpID).maybeSingle();
      if (!cred) return J({ error: "unknown_passkey" }, 400);
      const v = await verifyAuthenticationResponse({
        response: body.response, expectedChallenge: ch.challenge, expectedOrigin: origin, expectedRPID: rpID, requireUserVerification: false,
        authenticator: { credentialID: cred.credential_id, credentialPublicKey: fromB64u(cred.public_key), counter: Number(cred.counter), transports: cred.transports || undefined },
        credential: { id: cred.credential_id, publicKey: fromB64u(cred.public_key), counter: Number(cred.counter), transports: cred.transports || undefined },
      } as any);
      if (!v.verified) return J({ error: "not_verified" }, 400);
      await db.from("owner_passkeys").update({ counter: v.authenticationInfo.newCounter, last_used_at: new Date().toISOString() }).eq("id", cred.id);
      // この端末用の合言葉を発行する(最初の合言葉は表に出さない)
      const bytes = crypto.getRandomValues(new Uint8Array(24));
      const key = "sbo_" + [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
      const { error } = await db.from("owner_device_keys").insert({ key_hash: await sha256hex(key), owner_id: cred.owner_id, key_hint: key.slice(0, 10) + "…" });
      if (error) return J({ error: "save_failed" }, 500);
      return J({ ok: true, owner_key: key });
    }

    if (body.action === "list") {
      const owner = await ownerOf(req.headers.get("x-owner-key"));
      if (!owner) return J({ error: "invalid_owner_key" }, 401);
      const { data } = await db.from("owner_passkeys").select("id, created_at, last_used_at").eq("owner_id", owner.id).eq("rp_id", rpID).order("created_at");
      return J({ ok: true, passkeys: data || [] });
    }

    return J({ error: "unknown_action" }, 400);
  } catch (e) {
    console.error("passkey", e);
    return J({ error: "server_error" }, 500);
  }
});
