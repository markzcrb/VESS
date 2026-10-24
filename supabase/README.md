# VESS backend (Supabase)

Project: **vess** · ref `ysiuljqenyugxrwmajmo` · region eu-central-1 (Frankfurt)
API URL: `https://ysiuljqenyugxrwmajmo.supabase.co`
Publishable key (safe to ship in the app): `sb_publishable_vK6Sn8Pi2AIZsY0IEEjg2g_jABKWR9N`

## What the server does (and doesn't)
- The food log stays on the iPhone. The server keeps **only** auth users and a per-day AI usage counter (`ai_usage`).
- `coach`, `food-photo` and `chef` forward one request to the AI provider and return the answer. VESS stores and logs no prompts, context or photos. The provider processes them under its API terms.
- Provider is switched on the server only (`AI_PROVIDER` = `gemini` or `anthropic`); the app doesn't change. With no `AI_PROVIDER` set, whichever key exists is used (Gemini first).
- Daily limits (free beta): Coach 20, photo 10, AI Chef 10 (`ai_daily_limit`). Changed server-side only.

## Edge functions (all require a signed-in, non-anonymous user's JWT)
| Function | Request | Response |
|---|---|---|
| `POST /functions/v1/coach` | `{ messages: [{role: "user"\|"assistant", content}], context: {…summary…}, locale }` | `200 { reply, remaining }` |
| `POST /functions/v1/food-photo` | `{ image_base64, media_type: "image/jpeg", meal, locale }` (≤ ~1.5 MB) | `200 { items: [{name, amount, unit, kcal, protein_g, carbs_g, fat_g, confidence}], note, remaining, estimated: true }` |
| `POST /functions/v1/chef` | `{ pantry: [{name, use_soon}], must_use, meal, goal, servings, only_what_i_have, diet, avoid, allergens, protein_gap_g, locale }` | `200 { recipe: {name, minutes, servings, ingredients: [{name, amount, unit, grams, from_pantry, usda_hint}], steps, tip}, remaining, estimated: true }` (no nutrition: the app calculates it) |
| `POST /functions/v1/delete-account` | — | `200 { deleted: true }` |

Errors: `401 not_authenticated`, `429 daily_limit`, `400 bad_*`, `502 upstream` (quota refunded), `503 not_configured` (API key secret missing).
Headers: `Authorization: Bearer <access_token>`, `apikey: <publishable key>`.

## Secrets (Dashboard › Edge Functions › Secrets)
- `AI_PROVIDER`: `gemini` or `anthropic`
- Gemini: `GEMINI_API_KEY`; optional `GEMINI_COACH_MODEL`, `GEMINI_PHOTO_MODEL`, `GEMINI_CHEF_MODEL` (default `gemini-3.8-flash`)
- Claude: `ANTHROPIC_API_KEY`; optional `COACH_MODEL`, `PHOTO_MODEL`, `CHEF_MODEL` (default `claude-sonnet-5-5`)
- Note: on the Gemini API free tier Google may use prompts and photos to improve its products. Fine for testing with our own data; use a paid (billing-enabled) key before real users.

## Auth
- Sign in with Apple (native, `signInWithIdToken` / `grant_type=id_token`): enable the Apple provider with the app's bundle ID as Client ID. Needs a paid Apple Developer account.
- Email one-time code (fallback and for testing before the paid account): Email provider on; the email template must include `{{ .Token }}`.
