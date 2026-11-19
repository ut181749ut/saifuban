// スマホ通知(Webプッシュ)の送信。署名鍵はサーバーが初回に自分で作り、Vaultに保存する。
import * as webpush from "jsr:@negrel/webpush@0.5.0";

type DB = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: any; error: any }> };
export type PushTarget = { endpoint: string; keys: { p256dh: string; auth: string } };

let cached: { server: webpush.ApplicationServer; pub: string } | null = null;

const b64url = (u: Uint8Array) =>
  btoa(String.fromCharCode(...u)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

export async function pushServer(db: DB) {
  if (cached) return cached;
  let { data } = await db.rpc("sb_vapid_get");
  if (!data) {
    const kp = await webpush.generateVapidKeys({ extractable: true });
    const exported = await webpush.exportVapidKeys(kp);
    const raw = new Uint8Array(await crypto.subtle.exportKey("raw", kp.publicKey));
    ({ data } = await db.rpc("sb_vapid_init", { p_keys: JSON.stringify(exported), p_public: b64url(raw) }));
  }
  const vapidKeys = await webpush.importVapidKeys(data.keys, { extractable: false });
  const server = await webpush.ApplicationServer.new({
    contactInformation: Deno.env.get("SUPABASE_URL")!,
    vapidKeys,
  });
  cached = { server, pub: data.public };
  return cached;
}

export async function sendPush(db: DB, targets: PushTarget[], payload: Record<string, unknown>) {
  if (!targets?.length) return { sent: 0, gone: 0, failed: 0 };
  const { server } = await pushServer(db);
  const opts: any = { ttl: 24 * 60 * 60 };
  const U = (webpush as any).Urgency;
  if (U?.High) opts.urgency = U.High;
  let sent = 0, gone = 0, failed = 0;
  await Promise.all(targets.map(async (t) => {
    try {
      await server.subscribe(t).pushTextMessage(JSON.stringify(payload), opts);
      sent++;
    } catch (e) {
      if (e instanceof webpush.PushMessageError && e.isGone()) {
        gone++;
        await db.rpc("sb_push_gone", { p_endpoint: t.endpoint });
      } else {
        failed++;
        console.error("push", e instanceof Error ? e.message : e);
      }
    }
  }));
  return { sent, gone, failed };
}
