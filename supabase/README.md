# UMEVA backend (Supabase)

(The Supabase project is still named `vess`; renaming the app doesn't require changing it.)

Project: **vess** · ref `ysiuljqenyugxrwmajmo` · region eu-central-1 (Frankfurt)
API URL: `https://ysiuljqenyugxrwmajmo.supabase.co`
Publishable key (safe to ship in the app): `sb_publishable_vK6Sn8Pi2AIZsY0IEEjg2g_jABKWR9N`

## What the server does (and doesn't)
- The food log stays on the iPhone. The server keeps **only** auth users and a per-day AI usage counter (`ai_usage`).
- `coach`, `food-photo`, `menu` and `chef` forward one request to the AI provider and return the answer. UMEVA stores and logs no prompts, context or photos. The provider processes them under its API terms.
- Provider is switched on the server only (`AI_PROVIDER` = `gemini` or `anthropic`); the app doesn't change. With no `AI_PROVIDER` set, whichever key exists is used (Gemini first).
- Daily limits (free beta): Coach 20, photo 10 (a menu scan counts as a photo), AI Chef 10 (`ai_daily_limit`). Changed server-side only.
- Global circuit breaker: at most 5 000 AI calls per UTC day for the whole project (`ai_global_daily_limit`, table `ai_usage_global`, migration `20261028000000`). Protects the API bill from mass sign-ups. Raise it in a migration when real traffic needs it.

## Edge functions (all require a signed-in, non-anonymous user's JWT)
| Function | Request | Response |
|---|---|---|
| `POST /functions/v1/coach` | `{ messages: [{role: "user"\|"assistant", content}], context: {…summary…}, locale }` | `200 { reply, remaining }` |
| `POST /functions/v1/food-photo` | `{ image_base64, media_type: "image/jpeg", meal, locale }` (≤ ~1.5 MB) | `200 { items: [{name, amount, unit, kcal, protein_g, carbs_g, fat_g, confidence}], note, remaining, estimated: true }` |
| `POST /functions/v1/menu` | `{ image_base64, media_type: "image/jpeg"\|"image/png"\|"image/heic"\|"image/webp", locale }` (≤ ~2 MB) | `200 { title, dishes: [{name, section, menu_text, portion_g, kcal, protein_g, carbs_g, fat_g, ingredients, allergens (EU-14), contains (meat, pork, poultry, fish, shellfish, molluscs, egg, dairy, alcohol), confidence}], note, remaining }`. Counts as one photo estimate (`p_kind: "photo"`); refunded on upstream errors. Fit to diet, allergens and the avoid list is decided on the device. |
| `POST /functions/v1/chef` | `{ pantry: [{name, use_soon}], must_use, meal, goal, servings, only_what_i_have, diet, avoid, allergens, protein_gap_g, locale }` | `200 { recipe: {name, minutes, servings, ingredients: [{name, amount, unit, grams, from_pantry, usda_hint}], steps, tip}, remaining, estimated: true }` (no nutrition: the app calculates it) |
| `POST /functions/v1/delete-account` | — | `200 { deleted: true }` |

Errors: `401 not_authenticated`, `429 daily_limit`, `400 bad_*`, `502 upstream` (quota refunded), `503 not_configured` (API key secret missing), `503 service_busy` (global daily cap reached), `503 model_unavailable` (the configured Claude model id returned 404; quota refunded; no silent fallback to another model).
Headers: `Authorization: Bearer <access_token>`, `apikey: <publishable key>`.

## Secrets (Dashboard › Edge Functions › Secrets)
- `AI_PROVIDER`: `gemini` or `anthropic`
- Gemini: `GEMINI_API_KEY`; optional `GEMINI_COACH_MODEL`, `GEMINI_PHOTO_MODEL`, `GEMINI_MENU_MODEL` (falls back to the photo model), `GEMINI_CHEF_MODEL` (default `gemini-3.8-flash`)
- Claude: `ANTHROPIC_API_KEY`; optional `COACH_MODEL`, `PHOTO_MODEL`, `CHEF_MODEL`, `MENU_MODEL` (menu falls back to `PHOTO_MODEL`). Default for all four: `claude-haiku-5-5`. Coach sends `output_config.effort: "low"`; photo, menu and chef use a forced tool call for structured JSON. No temperature/top_p is sent.
- Switch to Claude: add `ANTHROPIC_API_KEY`, then set `AI_PROVIDER=anthropic`. Roll back: `AI_PROVIDER=gemini`. If photo/menu quality on Haiku isn't good enough, set `PHOTO_MODEL=claude-sonnet-5-5` without redeploying.
- Note: on the Gemini API free tier Google may use prompts and photos to improve its products. Fine for testing with our own data; use a paid (billing-enabled) key before real users.

## Prompt-injection guard
Every system prompt says the user's data (context, food names, pantry, photo and menu text) is data, never instructions. Outputs are schema-checked, clamped and length-limited on the server, and the app re-checks allergens, diet and nutrition on the device. The model has no tools that act.

## Auth
- Sign in with Apple (native, `signInWithIdToken` / `grant_type=id_token`): enable the Apple provider with the app's bundle ID as Client ID. Needs a paid Apple Developer account.
- Email one-time code (fallback and for testing before the paid account): Email provider on.
  - **Sending:** through Resend SMTP (Authentication › SMTP Settings), not Supabase's built-in mailer. Sender `"VESS" <vess@mail.commiscuisine.com>`. This address is temporary until VESS has its own domain; when it changes, verify the new domain in Resend and update the sender here and in SMTP Settings.
  - **Templates:** "Confirm sign up" and "Magic link / OTP" contain only the code, `{{ .Token }}`, and no link. The app has no deep-link handling for sign-in.
  - **Code:** Email OTP length 6 (Authentication › Providers › Email). The app accepts exactly 6 ASCII digits (`EmailCode` in `AuthClient.swift`): the field uses iOS one-time-code autofill (`.oneTimeCode`) and paste, drops spaces and dashes, and never sends anything shorter. Changing the length on the server means changing `EmailCode.length` and the "6-digit code" copy in `AccountView`.
  - **Site URL:** set to a real URL, not localhost.
