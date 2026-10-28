import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { Buffer } from "node:buffer";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@1";

// UMEVA entitlement sync.
// The app sends the StoreKit 2 `jwsRepresentation` of each current UMEVA+ entitlement
// (Transaction.currentEntitlements, after a purchase, on launch and on Transaction.updates).
// The server verifies Apple's signature and certificate chain, checks bundle, product and that the
// purchase was made for this account (appAccountToken == user id), then records it.
// The AI limits come only from these verified rows, never from the app.

const BUNDLE_ID = Deno.env.get("APP_BUNDLE_ID") ?? "app.umeva.ios";
const APP_APPLE_ID = Deno.env.get("APP_APPLE_ID") ? Number(Deno.env.get("APP_APPLE_ID")) : undefined;
const PRODUCTS = (Deno.env.get("PLUS_PRODUCT_IDS") ?? `${BUNDLE_ID}.plus.monthly,${BUNDLE_ID}.plus.annual`).split(",");
const ROOT_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
];
const LIMITS = {
  free: { coach: 3, photo: 1, chef: 1 },
  plus: { coach: 15, photo: 10, chef: 5 },
  tester: { coach: 50, photo: 30, chef: 30 },
} as const;

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

type Decoded = {
  originalTransactionId?: string; productId?: string; bundleId?: string; appAccountToken?: string;
  expiresDate?: number; revocationDate?: number; environment?: string;
};

// Tries Production, then Sandbox (TestFlight and sandbox testers). Xcode StoreKit testing only for testers.
async function verify(jws: string, allowXcode: boolean): Promise<Decoded> {
  const certs = await appleRoots();
  const envs: Environment[] = [Environment.PRODUCTION, Environment.SANDBOX];
  if (allowXcode) envs.push(Environment.XCODE);
  let last: unknown;
  for (const env of envs) {
    if (env === Environment.PRODUCTION && !APP_APPLE_ID) continue; // needs the App Store app id
    try {
      const v = new SignedDataVerifier(certs, true, env, BUNDLE_ID, env === Environment.PRODUCTION ? APP_APPLE_ID : undefined);
      return await v.verifyAndDecodeTransaction(jws) as Decoded;
    } catch (e) { last = e; }
  }
  throw last ?? new Error("unverified");
}

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user || user.is_anonymous) return json({ error: "not_authenticated" }, 401);
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  let body: { signed_transactions?: unknown };
  try { body = await req.json(); } catch { return json({ error: "bad_json" }, 400); }
  const list = Array.isArray(body.signed_transactions) ? body.signed_transactions.filter((s): s is string => typeof s === "string" && s.length < 20000).slice(0, 10) : [];

  const { data: tester } = await admin.from("ai_testers").select("user_id").eq("user_id", user.id).maybeSingle();
  const rejected: { reason: string }[] = [];

  for (const jws of list) {
    let t: Decoded;
    try { t = await verify(jws, !!tester); } catch { rejected.push({ reason: "unverified" }); continue; }
    if (t.bundleId !== BUNDLE_ID || !t.productId || !PRODUCTS.includes(t.productId) || !t.originalTransactionId) { rejected.push({ reason: "wrong_product" }); continue; }
    if (!t.appAccountToken || t.appAccountToken.toLowerCase() !== user.id.toLowerCase()) { rejected.push({ reason: "other_account" }); continue; }

    const { data: existing } = await admin.from("subscriptions").select("user_id").eq("original_transaction_id", t.originalTransactionId).maybeSingle();
    if (existing && existing.user_id !== user.id) { rejected.push({ reason: "other_account" }); continue; }

    const { error } = await admin.from("subscriptions").upsert({
      original_transaction_id: t.originalTransactionId,
      user_id: user.id,
      product_id: t.productId,
      environment: t.environment ?? "Production",
      expires_at: t.expiresDate ? new Date(t.expiresDate).toISOString() : null,
      revoked_at: t.revocationDate ? new Date(t.revocationDate).toISOString() : null,
      updated_at: new Date().toISOString(),
    });
    if (error) { console.error("entitlement upsert failed", error.code); rejected.push({ reason: "store_error" }); }
  }

  const { data: plan, error: pErr } = await admin.rpc("ai_user_plan", { p_user: user.id });
  if (pErr) return json({ error: "plan_error" }, 500);
  const { data: sub } = await admin.from("subscriptions").select("product_id, expires_at, environment")
    .eq("user_id", user.id).is("revoked_at", null).order("expires_at", { ascending: false }).limit(1).maybeSingle();

  const p = (plan === "plus" || plan === "tester") ? plan : "free";
  return json({
    plan: p,
    product_id: p === "free" ? null : sub?.product_id ?? null,
    expires_at: p === "free" ? null : sub?.expires_at ?? null,
    limits: LIMITS[p],
    rejected,
  });
});
