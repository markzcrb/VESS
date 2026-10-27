import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// VESS menu scan. Reads a photo of a restaurant menu and estimates every dish.
// Counts as one photo estimate. The photo is sent once and never stored or logged by VESS.
// The app decides fit (diet, allergens, avoid list, remaining targets) on the device.

const MAX_B64 = 2_800_000; // ~2 MB JPEG
const TYPES = ["image/jpeg", "image/png", "image/heic", "image/webp"];
const EU14 = ["gluten","crustaceans","eggs","fish","peanuts","soy","milk","nuts","celery","mustard","sesame","sulphites","lupin","molluscs"];
const KINDS = ["meat","pork","poultry","fish","shellfish","molluscs","egg","dairy","alcohol"];

const SYSTEM = `You read one photo of a restaurant menu for a nutrition app.
List every dish you can read on the menu, in menu order, max 40. Skip drinks unless the menu is only drinks. Never invent dishes that are not printed.
For each dish give: the name as printed (cleaned), the menu section, a typical restaurant portion in grams and typical nutrition for that portion (European restaurant portions, including usual sauces and sides named on the menu), the likely main ingredients, EU allergens it likely contains, and which of these it contains: meat, pork, poultry, fish, shellfish, molluscs, egg, dairy, alcohol.
Be honest: if the name is vague, lower the confidence. Names stay in the menu's language; "note" is in the requested language.
If the photo is not a menu, return an empty list with a short note.`;

function provider(): "gemini" | "anthropic" | null {
  const p = (Deno.env.get("AI_PROVIDER") ?? "").toLowerCase();
  if (p === "gemini" && Deno.env.get("GEMINI_API_KEY")) return "gemini";
  if (p === "anthropic" && Deno.env.get("ANTHROPIC_API_KEY")) return "anthropic";
  if (!p && Deno.env.get("GEMINI_API_KEY")) return "gemini";
  if (!p && Deno.env.get("ANTHROPIC_API_KEY")) return "anthropic";
  return null;
}

const DISH = {
  type: "object",
  properties: {
    name: { type: "string" },
    section: { type: "string" },
    menu_text: { type: "string", description: "the line as printed, incl. price" },
    portion_g: { type: "number" },
    kcal: { type: "number" }, protein_g: { type: "number" }, carbs_g: { type: "number" }, fat_g: { type: "number" },
    ingredients: { type: "array", items: { type: "string" } },
    allergens: { type: "array", items: { type: "string", enum: EU14 } },
    contains: { type: "array", items: { type: "string", enum: KINDS } },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
  },
  required: ["name", "portion_g", "kcal", "protein_g", "carbs_g", "fat_g", "ingredients", "allergens", "contains", "confidence"],
};
const RESULT = { type: "object", properties: { title: { type: "string" }, dishes: { type: "array", items: DISH }, note: { type: "string" } }, required: ["dishes"] };
const upper = (s: unknown): unknown => {
  if (Array.isArray(s)) return s.map(upper);
  if (s && typeof s === "object") {
    const o: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(s)) o[k] = k === "type" ? String(v).toUpperCase() : upper(v);
    return o;
  }
  return s;
};

async function viaGemini(img: string, mediaType: string, prompt: string) {
  const model = Deno.env.get("GEMINI_MENU_MODEL") ?? Deno.env.get("GEMINI_PHOTO_MODEL") ?? "gemini-3.8-flash";
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": Deno.env.get("GEMINI_API_KEY")!, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM }] },
      contents: [{ role: "user", parts: [{ inline_data: { mime_type: mediaType, data: img } }, { text: prompt }] }],
      generationConfig: { responseMimeType: "application/json", responseSchema: upper(RESULT), maxOutputTokens: 8192, temperature: 0.2 },
    }),
  });
  if (!r.ok) throw new Error(`gemini ${r.status}`);
  const out = await r.json();
  const text = (out.candidates?.[0]?.content?.parts ?? [])
    .filter((p: { text?: string; thought?: boolean }) => p.text && !p.thought)
    .map((p: { text: string }) => p.text).join("");
  return JSON.parse(text);
}

async function viaClaude(img: string, mediaType: string, prompt: string) {
  const model = Deno.env.get("MENU_MODEL") ?? Deno.env.get("PHOTO_MODEL") ?? "claude-sonnet-5-5";
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model, max_tokens: 6000, system: SYSTEM,
      tools: [{ name: "report_menu", description: "Report the dishes on the menu with estimates.", input_schema: RESULT }],
      tool_choice: { type: "tool", name: "report_menu" },
      messages: [{ role: "user", content: [
        { type: "image", source: { type: "base64", media_type: mediaType, data: img } },
        { type: "text", text: prompt },
      ] }],
    }),
  });
  if (!r.ok) throw new Error(`anthropic ${r.status}`);
  const out = await r.json();
  const use = (out.content ?? []).find((c: { type: string }) => c.type === "tool_use");
  if (!use) throw new Error("no tool output");
  return use.input;
}

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const num = (n: unknown, max: number) => { const v = Number(n); return Number.isFinite(v) ? Math.min(Math.max(Math.round(v * 10) / 10, 0), max) : 0; };
const str = (s: unknown, n: number) => String(s ?? "").replace(/[\u0000-\u001f]/g, " ").slice(0, n);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const which = provider();
  if (!which) return json({ error: "not_configured" }, 503);

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user || user.is_anonymous) return json({ error: "not_authenticated" }, 401);
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  let body: { image_base64?: string; media_type?: string; locale?: string };
  try { body = await req.json(); } catch { return json({ error: "bad_json" }, 400); }
  const img = body.image_base64 ?? "";
  const mediaType = body.media_type ?? "image/jpeg";
  if (!img || img.length > MAX_B64) return json({ error: "bad_image" }, 400);
  if (!TYPES.includes(mediaType)) return json({ error: "bad_media_type" }, 400);
  const prompt = `Language for note: ${str(body.locale ?? "en", 10)}.`;

  const { data: remaining, error: qErr } = await admin.rpc("consume_ai_quota", { p_user: user.id, p_kind: "photo" });
  if (qErr) return json({ error: "quota_error" }, 500);
  if (remaining === -1) return json({ error: "daily_limit", remaining: 0 }, 429);

  try {
    const raw = which === "gemini" ? await viaGemini(img, mediaType, prompt) : await viaClaude(img, mediaType, prompt);
    const dishes = (raw.dishes ?? []).slice(0, 40).map((d: Record<string, unknown>) => ({
      name: str(d.name, 80),
      section: str(d.section, 40),
      menu_text: str(d.menu_text, 160),
      portion_g: num(d.portion_g, 2000),
      kcal: num(d.kcal, 4000), protein_g: num(d.protein_g, 300), carbs_g: num(d.carbs_g, 500), fat_g: num(d.fat_g, 300),
      ingredients: (Array.isArray(d.ingredients) ? d.ingredients : []).slice(0, 12).map((x) => str(x, 40)),
      allergens: (Array.isArray(d.allergens) ? d.allergens : []).filter((a) => EU14.includes(String(a))),
      contains: (Array.isArray(d.contains) ? d.contains : []).filter((a) => KINDS.includes(String(a))),
      confidence: ["high", "medium", "low"].includes(String(d.confidence)) ? d.confidence : "low",
    })).filter((d: { name: string }) => d.name);
    return json({ title: str(raw.title, 80), dishes, note: str(raw.note, 200), remaining, estimated: true });
  } catch (e) {
    await admin.rpc("refund_ai_quota", { p_user: user.id, p_kind: "photo" });
    console.error("menu upstream failure", which, (e as Error).message);
    return json({ error: "upstream" }, 502);
  }
});
