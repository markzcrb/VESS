import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// VESS AI Chef. Writes one recipe draft from the user's pantry and choices.
// Provider (Gemini or Claude) set by AI_PROVIDER. Nothing is stored or logged by VESS.
// The app recalculates nutrition from its own food data and re-checks allergens;
// the model never supplies nutrition.

const SYSTEM = `You write one home-cooking recipe for the VESS nutrition app.
Hard rules, never broken:
- Never use any ingredient containing the listed allergens (EU allergen list), including hidden sources (soy sauce = soy + gluten, pesto = nuts + milk, worcestershire = fish, mayonnaise = eggs, most stock cubes = celery).
- Never use any ingredient in the avoid list.
- Follow the diet exactly (vegan: no animal products or honey; vegetarian: no meat or fish; pescatarian: fish and seafood allowed, no meat).
- Use every must-use item. Prefer pantry items marked use_soon, then other pantry items.
- If only_what_i_have is true, use only pantry items plus at most 2 missing items, and pantry basics (salt, pepper, water).
- Amounts in metric, for exactly the requested servings, realistic European home portions. grams = the weight used, raw or dry as bought (ml for liquids, grams = ml).
- 4 to 8 short imperative steps, oven in °C (fan), times given, plain calm language, no emoji. Chicken and pork cooked through.
- For each ingredient give usda_hint: a short generic description in USDA SR Legacy style ("Chickpeas, canned, drained", "Rice, white, long-grain, raw").
- Do not state calories or nutrition anywhere.
Answer in the requested language for names and steps; usda_hint always in English.`;

type Body = {
  pantry?: { name: string; use_soon?: boolean }[];
  must_use?: string[];
  meal?: string; goal?: string; servings?: number;
  only_what_i_have?: boolean;
  diet?: string; avoid?: string[]; allergens?: string[];
  protein_gap_g?: number; locale?: string;
};

const EU14 = ["gluten","crustaceans","eggs","fish","peanuts","soy","milk","nuts","celery","mustard","sesame","sulphites","lupin","molluscs"];
const MEALS = ["breakfast","lunch","dinner","snack"];
const GOALS = ["high_protein","lighter","quick","comfort","none"];
const str = (s: unknown, n: number) => String(s ?? "").replace(/[\u0000-\u001f]/g, " ").slice(0, n);

function provider(): "gemini" | "anthropic" | null {
  const p = (Deno.env.get("AI_PROVIDER") ?? "").toLowerCase();
  if (p === "gemini" && Deno.env.get("GEMINI_API_KEY")) return "gemini";
  if (p === "anthropic" && Deno.env.get("ANTHROPIC_API_KEY")) return "anthropic";
  if (!p && Deno.env.get("GEMINI_API_KEY")) return "gemini";
  if (!p && Deno.env.get("ANTHROPIC_API_KEY")) return "anthropic";
  return null;
}

const ING = {
  type: "object",
  properties: {
    name: { type: "string" },
    amount: { type: "number" },
    unit: { type: "string", enum: ["g", "ml", "piece", "slice", "tbsp", "tsp", "clove", "pinch"] },
    grams: { type: "number" },
    from_pantry: { type: "boolean" },
    usda_hint: { type: "string" },
  },
  required: ["name", "amount", "unit", "grams", "from_pantry", "usda_hint"],
};
const RECIPE = {
  type: "object",
  properties: {
    name: { type: "string" },
    minutes: { type: "integer" },
    servings: { type: "integer" },
    ingredients: { type: "array", items: ING },
    steps: { type: "array", items: { type: "string" } },
    tip: { type: "string" },
  },
  required: ["name", "minutes", "servings", "ingredients", "steps"],
};
const upper = (s: unknown): unknown => {
  if (Array.isArray(s)) return s.map(upper);
  if (s && typeof s === "object") {
    const o: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(s)) o[k] = k === "type" ? String(v).toUpperCase() : upper(v);
    return o;
  }
  return s;
};

async function viaGemini(prompt: string) {
  const model = Deno.env.get("GEMINI_CHEF_MODEL") ?? Deno.env.get("GEMINI_COACH_MODEL") ?? "gemini-3.8-flash";
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": Deno.env.get("GEMINI_API_KEY")!, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM }] },
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: "application/json", responseSchema: upper(RECIPE), maxOutputTokens: 4096, temperature: 0.7 },
    }),
  });
  if (!r.ok) throw new Error(`gemini ${r.status}`);
  const out = await r.json();
  const text = (out.candidates?.[0]?.content?.parts ?? [])
    .filter((p: { text?: string; thought?: boolean }) => p.text && !p.thought)
    .map((p: { text: string }) => p.text).join("");
  return JSON.parse(text);
}

async function viaClaude(prompt: string) {
  const model = Deno.env.get("CHEF_MODEL") ?? Deno.env.get("COACH_MODEL") ?? "claude-sonnet-5-5";
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model, max_tokens: 2000, system: SYSTEM,
      tools: [{ name: "write_recipe", description: "Return the recipe.", input_schema: RECIPE }],
      tool_choice: { type: "tool", name: "write_recipe" },
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!r.ok) throw new Error(`anthropic ${r.status}`);
  const out = await r.json();
  const use = (out.content ?? []).find((c: { type: string }) => c.type === "tool_use");
  if (!use) throw new Error("no tool output");
  return use.input;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const num = (n: unknown, max: number) => {
  const v = Number(n);
  return Number.isFinite(v) ? Math.min(Math.max(Math.round(v * 10) / 10, 0), max) : 0;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const which = provider();
  if (!which) return json({ error: "not_configured" }, 503);

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user || user.is_anonymous) return json({ error: "not_authenticated" }, 401);
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  let b: Body;
  try { b = await req.json(); } catch { return json({ error: "bad_json" }, 400); }
  const pantry = (b.pantry ?? []).slice(0, 80).map((p) => ({ name: str(p.name, 60), use_soon: !!p.use_soon })).filter((p) => p.name);
  const mustUse = (b.must_use ?? []).slice(0, 10).map((s) => str(s, 60)).filter(Boolean);
  const avoid = (b.avoid ?? []).slice(0, 40).map((s) => str(s, 40)).filter(Boolean);
  const allergens = (b.allergens ?? []).filter((a) => EU14.includes(a));
  const meal = MEALS.includes(String(b.meal)) ? b.meal : "dinner";
  const goal = GOALS.includes(String(b.goal)) ? b.goal : "none";
  const servings = Math.min(Math.max(Math.round(Number(b.servings) || 2), 1), 8);
  if (!pantry.length && !mustUse.length) return json({ error: "bad_pantry" }, 400);

  const prompt = JSON.stringify({
    language: str(b.locale ?? "en", 10), meal, goal, servings,
    only_what_i_have: !!b.only_what_i_have,
    diet: str(b.diet ?? "omnivore", 40), allergens, avoid,
    protein_gap_g: b.protein_gap_g == null ? null : num(b.protein_gap_g, 300),
    must_use: mustUse, pantry,
  });

  const { data: remaining, error: qErr } = await admin.rpc("consume_ai_quota", { p_user: user.id, p_kind: "chef" });
  if (qErr) return json({ error: "quota_error" }, 500);
  if (remaining === -1) return json({ error: "daily_limit", remaining: 0 }, 429);

  try {
    const raw = which === "gemini" ? await viaGemini(prompt) : await viaClaude(prompt);
    const ingredients = (raw.ingredients ?? []).slice(0, 25).map((i: Record<string, unknown>) => ({
      name: str(i.name, 60), amount: num(i.amount, 5000),
      unit: ["g","ml","piece","slice","tbsp","tsp","clove","pinch"].includes(String(i.unit)) ? i.unit : "g",
      grams: num(i.grams, 5000), from_pantry: !!i.from_pantry, usda_hint: str(i.usda_hint, 80),
    })).filter((i: { name: string }) => i.name);
    const steps = (raw.steps ?? []).slice(0, 12).map((s: unknown) => str(s, 400)).filter(Boolean);
    if (!ingredients.length || !steps.length) throw new Error("empty recipe");
    return json({
      recipe: {
        name: str(raw.name, 80), minutes: Math.min(Math.max(Number(raw.minutes) || 30, 5), 240),
        servings, ingredients, steps, tip: raw.tip ? str(raw.tip, 200) : null,
      },
      remaining, estimated: true,
    });
  } catch (e) {
    await admin.rpc("refund_ai_quota", { p_user: user.id, p_kind: "chef" });
    console.error("chef upstream failure", which, (e as Error).message);
    return json({ error: "upstream" }, 502);
  }
});
