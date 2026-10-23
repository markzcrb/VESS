# App Store privacy: labels, policy text, review notes

The AI processor is named in the app from one constant, `AIProcessor.displayName` (now "Google Gemini"). The server chooses the provider (`AI_PROVIDER`, see `supabase/README.md`). **Processor today: Google (Gemini API).** If we switch to Claude, this changes to **Anthropic (Claude API)**, in this file, in the published policy and in the app constant, and the consent version is bumped so everyone is asked again.

## Privacy nutrition label (App Store Connect)
| Data type | Collected | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|---|
| Contact Info › Email Address | Yes, only with an account (email code or Sign in with Apple, which may be a private relay address) | Yes | No | App Functionality (sign-in for Coach and photo estimates) |
| Identifiers › User ID | Yes, only with an account: the account's ID, used to count daily AI uses | Yes | No | App Functionality |
| User Content › Photos or Videos | Yes, only when the user takes or picks a meal photo for an estimate. Sent once for processing, not stored by VESS | Yes (sent with the signed-in request) | No | App Functionality |
| Health & Fitness › Health, Fitness | Yes, only when the user asks Coach: a summary of recent logs (targets, intake totals and averages, meals, habits, workouts, supplements, steps; cycle day and next estimated window only if "Share cycle with Coach" is on). Sent once for processing, not stored by VESS | Yes (sent with the signed-in request) | No | App Functionality |
| User Content › Other User Content | Yes, only when the user asks Coach: the question and the conversation so far. Sent once, not stored by VESS | Yes | No | App Functionality |
| Search History | Yes: food search words and scanned barcodes are sent to Open Food Facts to find products | No | No | App Functionality |

Everything VESS stores (profile, food log, drinks, workouts, pantry, plans, supplements, cycle days, habits, the Coach conversation) stays on the iPhone. The server keeps only the account (user ID and email) and a per-day count of AI uses (`ai_usage`). Apple Health data is read on the device and not kept; only Coach's summary includes steps, when the user asks. No analytics, no ads, no tracking, no third-party SDKs.

**Third-party processor:** Google (Gemini API), for Coach answers and photo estimates, through VESS's server (Supabase, EU, Frankfurt). Google processes the requests under its API terms. If the provider changes to Anthropic (Claude API), update this line.

## Privacy policy text (to add to the published policy)
> **Account.** You only need an account for Coach and photo estimates. You sign in with a one-time code by email (or Sign in with Apple). We keep your email address (or Apple's private relay address), your account ID and a count of how many AI requests you made each day, so we can apply the free daily limits. Your food log and other data are not stored on our server. You can delete your account at any time in You › Account; this removes your email, account ID and usage counts from our server. Data on your iPhone stays until you also choose Delete all data.
>
> **Coach.** Coach is optional. Before your first question, VESS asks for your consent. When you ask, VESS sends your question, the conversation so far, and a summary of your recent logs (your targets, today's totals, 7-day averages, today's meals, habits, workouts, supplements and steps; your cycle day and next estimated window only if you turn on Share cycle with Coach) through VESS's server to Google's Gemini API for an answer. VESS doesn't store your questions, the summary or the answers on its server; the conversation is kept only on your iPhone, and you can clear it in Coach. Google processes the request under its API terms. You can see exactly what is sent in Coach › What Coach sees, and turn Coach off in You › Privacy and data.
>
> **Photo estimates.** Photo estimates are optional. Before the first one, VESS asks for your consent. When you take or pick a photo, VESS makes it smaller, removes its location and camera details, and sends it once through VESS's server to Google's Gemini API to estimate the food in it. VESS doesn't store the photo, on the server or on your iPhone. Nothing is added to your log until you review and confirm the estimate. Google processes the request under its API terms. You can turn photo estimates off in You › Privacy and data.
>
> **Open Food Facts.** When you search for a food or scan a barcode, VESS sends the search words or the barcode to Open Food Facts (openfoodfacts.org) to find the product. Nothing else is sent: no account, name, location or health data. Products found are kept on your iPhone so they work offline. Open Food Facts' own privacy policy applies to these requests.
>
> **Cycle tracking.** Off unless you turn it on. Cycle days stay on your iPhone and are never shared with Apple Health. They're sent nowhere, except that Coach receives your current cycle day and the next estimated window with a question if you turn on Share cycle with Coach (off by default). You can export them with Export my data and remove them with Delete cycle data or Delete all data.

## Consent (guideline 5.1.2(i))
- Before the first Coach question and the first photo estimate, a one-time sheet says what is sent (Coach: the question, the conversation and a summary of recent logs; photo: the photo), to whom ("Google Gemini, through VESS's server"), and that "VESS doesn't store it. Google processes it under its API terms." Buttons: Allow / Not now. Not now sends nothing.
- Consent is stored per feature and per processor (consent version). Switching provider bumps the version, so the sheet is shown again.
- Revocable at any time in You › Privacy and data › AI features.

## Account deletion (guideline 5.1.1(v))
- You › Account › Delete account calls the `delete-account` function, which deletes the user in Supabase Auth; the `ai_usage` rows go with it (on delete cascade). The app then signs out.
- The dialog offers "Delete account" (the log stays on the iPhone) and "Delete account and all data" (also runs Delete all data).

## Review notes (App Review Information › Notes)
> Coach and photo estimates are optional and need a free account (email one-time code; Sign in with Apple when enabled). Before the first use of each, the app asks for consent and names the processor (Google Gemini, through our server). Requests are forwarded once and not stored by us; the server keeps only the account and a daily usage counter (free beta limits: Coach 20, photos 10 per day). Nothing from a photo estimate is logged without the user's confirmation. Accounts can be deleted in the app (You › Account › Delete account).
>
> Cycle tracking is opt-in (You › Preferences). Cycle data is stored only on the device and is not shared with HealthKit; it is sent to Coach only if the user turns on "Share cycle with Coach" (off by default). The estimate is labelled as an estimate, not medical advice and not contraception; there are no fertility, ovulation or pregnancy features. HealthKit is read-only (steps, workouts, active energy, weight).
>
> To review without an email inbox, use the demo account we provide in App Review Information (sign-in code via the email field).
