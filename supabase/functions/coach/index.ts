import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// VESS Coach. Stateless proxy to an AI provider (Gemini or Claude, set by AI_PROVIDER).
// Nothing from the request (messages, context) is stored or logged by VESS.

const MAX_MESSAGES = 20;
const MAX_CHARS = 4000;
const MAX_CONTEXT = 16000;

const SYSTEM = `You are the VESS Coach inside a nutrition and wellness app.
Voice: calm, specific, brief (2-5 short sentences unless asked for more). Plain words, no hype, no emoji.
Use ONLY the user's data in <context> plus general nutrition knowledge. If the data doesn't show something, say so instead of guessing.
Patterns are patterns, not causes; never claim one thing caused another.
You are not a doctor or dietitian. No diagnoses, no medication or supplement dosing, no treatment plans. For symptoms, medical conditions, pregnancy or anything urgent, suggest a professional.
Never encourage very low intake, skipping meals to compensate, purging, or exercise as punishment. If the user shows signs of disordered eating, be kind, give no numbers or targets, and suggest talking to a professional.
Alcohol: neutral, no advice to drink.
The cycle data, if present, is an estimate; never mention fertility, ovulation or contraception.
If <context> has "pregnant": true: never suggest weight loss, eating less, a calorie deficit or BMI; never comment on weight gain; leave alcohol out of every suggestion; for food safety or specific nutrient questions (fish, caffeine, supplements), give general guidance and suggest asking their midwife or doctor.
Food suggestions must follow <context> "diet", never include "allergens" (EU list, including hidden sources such as soy sauce, pesto, mayonnaise, stock cubes) and never include anything in "avoid". Pescatarian = fish and seafood, no meat or poultry. If unsure whether a food fits, leave it out.
Numbers: use the totals and averages already given in <context>; don't recompute or estimate missing days. If a day has no data, say so.
Formatting: plain sentences; at most one short list (- item), **bold** for at most one key number. No headings, no tables.
Visuals: whenever the answer is about one of these metrics, add exactly one token for it on its own line (two at most per answer): [[chart:METRIC:RANGE]]. METRIC is one of steps, active_energy, workouts, energy, protein, carbs, fat, fiber, sugar, water, caffeine, sleep, hrv, resting_hr, stress, weight, bmi, habits, supplements. RANGE is today (a ring against the target), 7d or 30d (daily bars or a line). Use today for "today" questions, 7d by default otherwise. The app draws it from the user's own data, so never describe values you don't have in <context>.
Answer in the user's language.`;

type Msg = { role: "user" | "assistant"; content: string };

function provider(): "gemini" | "anthropic" | null {
  const p = (Deno.env.get("AI_PROVIDER") ?? "").toLowerCase();
  if (p === "gemini" && Deno.env.get("GEMINI_API_KEY")) return "gemini";
  if (p === "anthropic" && Deno.env.get("ANTHROPIC_API_KEY")) return "anthropic";
  if (!p && Deno.env.get("GEMINI_API_KEY")) return "gemini";
  if (!p && Deno.env.get("ANTHROPIC_API_KEY")) return "anthropic";
  return null;
}

async function askGemini(system: string, msgs: Msg[]): Promise<string> {
  const model = Deno.env.get("GEMINI_COACH_MODEL") ?? "gemini-3.8-flash";
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": Deno.env.get("GEMINI_API_KEY")!, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: msgs.map((m) => ({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.content }] })),
      generationConfig: { maxOutputTokens: 2048, temperature: 0.6 },
    }),
  });
  if (!r.ok) throw new Error(`gemini ${r.status}`);
  const out = await r.json();
  return (out.candidates?.[0]?.content?.parts ?? [])
    .filter((p: { text?: string; thought?: boolean }) => p.text && !p.thought)
    .map((p: { text: string }) => p.text).join("\n").trim();
}

async function askClaude(system: string, msgs: Msg[]): Promise<string> {
  const model = Deno.env.get("COACH_MODEL") ?? "claude-sonnet-5-5";
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model, max_tokens: 600, system, messages: msgs }),
  });
  if (!r.ok) throw new Error(`anthropic ${r.status}`);
  const out = await r.json();
  return (out.content ?? []).filter((c: { type: string }) => c.type === "text")
    .map((c: { text: string }) => c.text).join("\n").trim();
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

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

  let body: { messages?: { role: string; content: string }[]; context?: unknown; locale?: string };
  try { body = await req.json(); } catch { return json({ error: "bad_json" }, 400); }

  const msgs: Msg[] = (body.messages ?? []).slice(-MAX_MESSAGES)
    .filter((m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content.trim())
    .map((m) => ({ role: m.role as Msg["role"], content: m.content.slice(0, MAX_CHARS) }));
  while (msgs.length && msgs[0].role !== "user") msgs.shift();
  if (!msgs.length || msgs[msgs.length - 1].role !== "user") return json({ error: "bad_messages" }, 400);
  const context = JSON.stringify(body.context ?? {}).slice(0, MAX_CONTEXT);
  const system = `${SYSTEM}\nLocale: ${body.locale ?? "en"}.\n<context>${context}</context>`;

  const { data: remaining, error: qErr } = await admin.rpc("consume_ai_quota", { p_user: user.id, p_kind: "coach" });
  if (qErr) return json({ error: "quota_error" }, 500);
  if (remaining === -1) return json({ error: "daily_limit", remaining: 0 }, 429);

  try {
    const text = which === "gemini" ? await askGemini(system, msgs) : await askClaude(system, msgs);
    if (!text) throw new Error("empty");
    return json({ reply: text, remaining });
  } catch (e) {
    await admin.rpc("refund_ai_quota", { p_user: user.id, p_kind: "coach" });
    console.error("coach upstream failure", which, (e as Error).message);
    return json({ error: "upstream" }, 502);
  }
});
