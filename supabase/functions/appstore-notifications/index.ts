import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { Buffer } from "node:buffer";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@1";

// App Store Server Notifications V2 for UMEVA+.
// Deploy with verify_jwt = false: Apple calls it without a Supabase token. Every request is
// authenticated by verifying Apple's signature on `signedPayload`; anything unverified is ignored.
// Set this URL in App Store Connect › App › App Information › App Store Server Notifications
// (Production and Sandbox): https://<project>.supabase.co/functions/v1/appstore-notifications

const BUNDLE_ID = Deno.env.get("APP_BUNDLE_ID") ?? "app.umeva.ios";
const APP_APPLE_ID = Deno.env.get("APP_APPLE_ID") ? Number(Deno.env.get("APP_APPLE_ID")) : undefined;
const PRODUCTS = (Deno.env.get("PLUS_PRODUCT_IDS") ?? `${BUNDLE_ID}.plus.monthly,${BUNDLE_ID}.plus.annual`).split(",");
const ROOT_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
];

let roots: Buffer[] | null = null;
async function appleRoots(): Promise<Buffer[]> {
  if (roots) return roots;
  const out: Buffer[] = [];
  for (const u of ROOT_URLS) {
    const r = await fetch(u);
    if (r.ok) out.push(Buffer.from(new Uint8Array(await r.arrayBuffer())));
  }
  if (!out.length) throw new Error("apple_roots_unavailable");
  roots = out;
  return out;
}

function verifiers(certs: Buffer[]) {
  const list = [new SignedDataVerifier(certs, true, Environment.SANDBOX, BUNDLE_ID)];
  if (APP_APPLE_ID) list.unshift(new SignedDataVerifier(certs, true, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID));
  return list;
}

type Tx = { originalTransactionId?: string; productId?: string; bundleId?: string; appAccountToken?: string; expiresDate?: number; revocationDate?: number; environment?: string };

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method_not_allowed", { status: 405 });
  let signedPayload: string | undefined;
  try { signedPayload = (await req.json()).signedPayload; } catch { return new Response("bad_json", { status: 400 }); }
  if (typeof signedPayload !== "string" || signedPayload.length > 100000) return new Response("bad_payload", { status: 400 });

  const certs = await appleRoots();
  let verifier: SignedDataVerifier | null = null;
  // deno-lint-ignore no-explicit-any
  let note: any = null;
  for (const v of verifiers(certs)) {
    try { note = await v.verifyAndDecodeNotification(signedPayload); verifier = v; break; } catch { /* try next */ }
  }
  // Unverified: answer 200 so Apple doesn't retry forged traffic, and change nothing.
  if (!note || !verifier) { console.error("asn unverified"); return new Response("ok"); }

  const signedTx = note.data?.signedTransactionInfo;
  if (!signedTx) return new Response("ok");
  let t: Tx;
  try { t = await verifier.verifyAndDecodeTransaction(signedTx) as Tx; } catch { console.error("asn tx unverified"); return new Response("ok"); }
  if (t.bundleId !== BUNDLE_ID || !t.productId || !PRODUCTS.includes(t.productId) || !t.originalTransactionId) return new Response("ok");

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const row = {
    product_id: t.productId,
    environment: t.environment ?? "Production",
    expires_at: t.expiresDate ? new Date(t.expiresDate).toISOString() : null,
    revoked_at: t.revocationDate ? new Date(t.revocationDate).toISOString() : null,
    updated_at: new Date().toISOString(),
  };
  const { data: existing } = await admin.from("subscriptions").select("user_id").eq("original_transaction_id", t.originalTransactionId).maybeSingle();
  if (existing) {
    await admin.from("subscriptions").update(row).eq("original_transaction_id", t.originalTransactionId);
  } else if (t.appAccountToken) {
    // First sight of this purchase: bind it to the account it was bought for, if that account exists.
    const { data: u } = await admin.auth.admin.getUserById(t.appAccountToken.toLowerCase());
    if (u?.user) await admin.from("subscriptions").insert({ original_transaction_id: t.originalTransactionId, user_id: u.user.id, ...row });
  }
  console.log("asn", note.notificationType, note.subtype ?? "", t.environment ?? "");
  return new Response("ok");
});
