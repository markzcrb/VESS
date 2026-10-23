# VESS backend (Supabase)

Project: **vess** · ref `ysiuljqenyugxrwmajmo` · region eu-central-1 (Frankfurt)
API URL: `https://ysiuljqenyugxrwmajmo.supabase.co`
Publishable key (safe to ship in the app): `sb_publishable_vK6Sn8Pi2AIZsY0IEEjg2g_jABKWR9N`

## What the server does (and doesn't)
- The food log stays on the iPhone. The server keeps **only** auth users and a per-day AI usage counter (`ai_usage`).
- `coach` and `food-photo` forward one request to the Claude API (Anthropic) and return the answer. VESS stores and logs no prompts, context or photos. Anthropic processes them under its API terms.
- Daily limits (free beta): Coach 20, photo 10 (`ai_daily_limit`). Changed server-side only.

## Edge functions (all require a signed-in, non-anonymous user's JWT)
| Function | Request | Response |
|---|---|---|
| `POST /functions/v1/coach` | `{ messages: [{role: "user"\|"assistant", content}], context: {…summary…}, locale }` | `200 { reply, remaining }` |
| `POST /functions/v1/food-photo` | `{ image_base64, media_type: "image/jpeg", meal, locale }` (≤ ~1.5 MB) | `200 { items: [{name, amount, unit, kcal, protein_g, carbs_g, fat_g, confidence}], note, remaining, estimated: true }` |
| `POST /functions/v1/delete-account` | — | `200 { deleted: true }` |

Errors: `401 not_authenticated`, `429 daily_limit`, `400 bad_*`, `502 upstream` (quota refunded), `503 not_configured` (API key secret missing).
Headers: `Authorization: Bearer <access_token>`, `apikey: <publishable key>`.

## Secrets (Dashboard › Edge Functions › Secrets)
- `ANTHROPIC_API_KEY` (required)
- `COACH_MODEL`, `PHOTO_MODEL` (optional, default `claude-sonnet-5-5`)

## Auth
- Sign in with Apple (native, `signInWithIdToken` / `grant_type=id_token`): enable the Apple provider with the app's bundle ID as Client ID. Needs a paid Apple Developer account.
- Email one-time code (fallback and for testing before the paid account): Email provider on; the email template must include `{{ .Token }}`.
