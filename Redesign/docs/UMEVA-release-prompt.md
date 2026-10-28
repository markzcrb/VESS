# UMEVA (was VESS, briefly HEMAX): rename, brand screens, AI errors, security and App Store pass

Branch `redesign`. Never push to `main`, never force-push. Small commits, one per step, tests green after each. Keep every existing feature working. When a step needs a decision from Mark, do the safe default below and list it in the report instead of stopping.

Design source: Figma file `6V1ynZXb5VWWowRvUqMJ7j`, section "UMEVA · Brand, icon, first launch and welcome" (node `239:5535`): B01 Launch light `239:5536`, B01D Launch dark `239:5555`, B02 First launch `240:5516`, B03 Welcome after onboarding `240:5554`, B04 UMEVA+ welcome `240:5604`, icon board `239:5574`. PNG exports: `Redesign/Design/screens/B01…B04*.png`. Brand files: `Redesign/Brand/`.

## Step 0. Commit what is already in the working tree
I (the backend side) wrote these files; commit them as they are, one commit, "chore(server): Haiku 5.5 defaults, service_busy and model_unavailable, global AI cap, injection guards; UMEVA brand assets and screens":
- `supabase/functions/{coach,food-photo,chef,menu}/index.ts` (already deployed: coach v9, food-photo v6, chef v2, menu v2)
- `supabase/migrations/20261025000000_ai_usage_read_only_for_users.sql`, `supabase/migrations/20261028000000_ai_global_daily_circuit_breaker.sql` (already applied)
- `supabase/README.md`
- `Redesign/Brand/*`, `Redesign/Design/screens/B0*.png`
- Delete the old HEMAX files that the UMEVA ones replace: `Redesign/Brand/hemax-*.svg`, `Redesign/Design/screens/B04-hemax-plus-welcome.png` (I can't delete on this Mac from my side). Commit `Redesign/docs/UMEVA-release-prompt.md` too and delete `Redesign/docs/HEMAX-release-prompt.md`.
Don't edit the server files.

**Name decision:** the app is now **UMEVA** (always written UMEVA in text; the logo draws it as UMEVΛ). Web: `umeva.app` (Mark is registering it). Use `https://umeva.app/privacy` and `https://umeva.app/terms` as the URL constants, marked TODO until the pages are live; App Store review needs them reachable.

## Step 1. Rename VESS → UMEVA (user-facing only)
- `INFOPLIST_KEY_CFBundleDisplayName = UMEVA` (both configurations). Every user-facing string: "VESS" → "UMEVA", "VESS+" → "UMEVA+" (String Catalog, usage descriptions, accessibility labels, notifications, consent sheet, paywall, Settings, review notes in `Redesign/docs/*.md`). Check with a grep that no user-visible "VESS" is left; list any you leave on purpose.
- Keep code identifiers, the target, folders, the bundle ID `com.markgerasimovpersonalteam.VESS` and the product IDs as they are. Mark decides the final bundle ID and product IDs before they're created in App Store Connect (both are permanent there); put this in the report.
- `Logger(subsystem:)`: use `Bundle.main.bundleIdentifier ?? "UMEVA"` in one shared place.

## Step 2. Brand foundation
- Colors in the design system (asset catalog, light/dark where noted): `brandPearl #F4F1EC`, `brandStone #E4DED5`, `brandInk #141414`, `brandInkSoft #6E6A64`, `brandGraphite #0F1012`, `brandPearlSoft #B9B4AC`. Brand screens only; don't recolor the rest of the app.
- Wordmark `UMEVAWordmark`: a SwiftUI `Shape` drawn from these stroked paths (viewBox 592×100, stroke width 5, miter joins, butt caps), scaled to the frame, tinted by foreground style. This replaces `VESSWordmark` everywhere.
  `M2.5 0V65A32.5 32.5 0 0 0 67.5 65V0` (U) · `M127.5 100V2.5L170 70L212.5 2.5V100` (M) · `M272.5 0V100M270 2.5H330M270 50H325M270 97.5H330` (E) · `M385 0L423 97.5L461 0` (V) · `M516 100L554 2.5L592 100` (Λ)
  The Λ ("A") has no crossbar on purpose; V and Λ mirror each other. Source: `Redesign/Brand/umeva-wordmark-ink.svg`. Accessibility label "UMEVA".
- Monogram `UMEVAMonogram`: `M22 80L50 18L78 80` in a 100×100 box, stroke 4.
- Silk backgrounds: `Redesign/Brand/silk-pearl.png` and `silk-graphite.png` into the asset catalog as JPEG/HEIC around 300 KB or less each (they're full-bleed photos, so no PNG). Pearl is used in light mode and graphite in dark mode. The UMEVA+ welcome always uses graphite.

## Step 3. Launch screen (B01, B01D)
- The system launch screen can't show a photo that changes with appearance cleanly, so use `UILaunchScreen` with `UIColorName = LaunchBackground` (pearl in light, graphite in dark) and `UIImageName = LaunchWordmark` (a vector PDF or SVG asset made from the wordmark, ink for light and pearl for dark, about 150 pt wide, centered). With the generated Info.plist, add a minimal `Info.plist` that only holds `UILaunchScreen`, or set it through build settings if that works. Check that it really shows on a cold launch on a device; the launch screen cache may need a reinstall.
- Then an in-app splash (B01) appears for the first frame of `AppRootView`: silk image full-bleed, wordmark in the same place and size as on the launch screen, so the handoff doesn't jump. It crossfades into the app as soon as the store is ready, after at most 0.6 s and with no artificial wait. With Reduce Motion it's a plain fade. Make sure it doesn't slow launch: measure with `LaunchTiming` before and after.

## Step 4. App icon
`VESS/Assets.xcassets/AppIcon.appiconset`: a single-size 1024 icon with three appearances: Any `Redesign/Brand/AppIcon-1024-light.png`, Dark `…-dark.png` and Tinted `…-tinted.png`. They're RGB with no alpha. Write `Contents.json` by hand with the `appearances` luminosity entries. Check the Home Screen in light, dark and tinted modes on the device, and attach a screenshot.

## Step 5. Screens
Match the Figma frames. Use Dynamic Type through AX5 (content scrolls, buttons stay reachable), VoiceOver order top to bottom, 44 pt targets, and light and dark modes.
- **B02 First launch**, shown only before onboarding: silk background on the top part, wordmark, the headline "Your body, in balance.", the line "Food, drinks, sleep and recovery in one calm place. Your log stays on this iPhone.", a primary "Get started" button that opens the existing onboarding, a secondary "I already use UMEVA" that goes to sign-in and then onboarding with what can be restored, and a caption with Terms and Privacy Policy links (the Privacy URL is a constant; see the report).
- **B03 Welcome after onboarding**: "ALL SET", "Welcome, {first name}." ("Welcome." with no name), the list of the targets that were actually computed (energy, protein, water, steps, sleep; leave out any that aren't set), a primary "Open Today" button, and a secondary "Connect Apple Health first" button that's hidden when Health is already connected. Shown once.
- **B04 UMEVA+ welcome**: shown once per `originalTransactionID`, right after a purchase verified by `.verified`, never on restore. The background is always graphite silk.
  - Badge: "UMEVA+ · TRIAL ACTIVE" during an intro offer, "UMEVA+ · ACTIVE" otherwise.
  - Dates come from the transaction and renewal info: trial end, or next renewal. The reminder line appears only if the trial reminder is really scheduled, with the date it's scheduled for.
  - Four check rows with the real UMEVA+ limits. Take them from one constant that matches the server, and never hardcode them in two places.
  - "Ask Coach something" opens Coach, and "Done" closes.
  - Caption "Manage or cancel any time in Settings." with a button that opens `showManageSubscriptions`.

## Step 6. New server errors
The shared AI client should map `503 {"error":"service_busy"}` and `503 {"error":"model_unavailable"}` to one calm message: "AI is busy right now. Try again in a little while. This didn't use an estimate." Use it in Coach, photo, menu and Chef. Keep `not_configured` as it is. Add unit tests for the mapping of 401, 429, 503 (each of the three codes) and 502.

## Step 7. AI disclosure must match what is sent (privacy, App Review 5.1.1/5.1.2)
- `AIProcessor` stays the one place for the processor. Add a second case for Anthropic ("Anthropic Claude" / "Anthropic"), but keep **Google Gemini active**. Switching is one constant plus a bumped consent version, which asks everyone again. Write in `APP-STORE-PRIVACY.md` that the app update ships first and only then does Mark set `AI_PROVIDER=anthropic`.
- The Coach consent text "What is sent" and `NSHealthShareUsageDescription` are out of date: Coach's context now includes sleep, HRV, resting heart rate, the stress estimate, weight/BMI, water, caffeine, steps and workouts (see `CoachContextMetrics`). Make the consent text, the usage description, `Redesign/docs/APP-STORE-PRIVACY.md` (label rows and the Apple Health paragraph) and the policy draft list exactly what `CoachContext` encodes. Add a unit test that encodes a full `CoachContext` and checks the top-level keys against the list shown in the consent text, so they can't drift again. Bump the Coach consent version, because the scope grew.
- Menu scan uses the photo consent. Say "a photo of a meal or a menu".

## Step 8. App-side security pass (fix what's safe, report the rest)
Check each item, fix it, and add a test where possible:
1. Tokens: access and refresh tokens are only in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Sign-out and account deletion remove them. Nothing auth-related is in UserDefaults or logs.
2. Logs: no email, food names, health values, prompts, tokens or server bodies with `privacy: .public`. Error descriptions from URLSession or the server must not include response bodies.
3. StoreKit 2:
   - `Transaction.updates` is listened to from app launch (not only while the paywall is open), and every verified transaction is `finish()`ed.
   - Entitlement means verified, not revoked (`revocationDate == nil`), not expired, and not upgraded (`isUpgraded`).
   - Handle `.pending` and `.userCancelled`. Restore calls `AppStore.sync()` and shows the result.
   - The paywall shows `displayPrice` with the period, the trial terms, the auto-renew line, and Terms (EULA) and Privacy Policy links (Guideline 3.1.2).
   - Run the StoreKit tests on `VESS.storekit`, including the trial, renewal, refund/revocation and Ask to Buy cases.
4. Paid limits are not enforced by the server yet (it uses the free limits for everyone). Don't build a workaround in the app. Report it as a release blocker for paid tiers: it needs App Store Server API verification on the server.
5. Privacy manifest: add `VESS/PrivacyInfo.xcprivacy`:
   - `NSPrivacyTracking` false and no tracking domains.
   - Collected data types matching `APP-STORE-PRIVACY.md`.
   - Required-reason APIs for what the code really uses: UserDefaults `CA92.1`, and file timestamp, system boot time or disk space only if a grep shows them (for example `systemUptime` in `LaunchTiming` → `35F9.1`).
   - Check that it's in the app target's Copy Bundle Resources.
6. Orientation: iPhone currently allows landscape. Unless every screen has been checked in landscape, set iPhone to portrait only.
7. Account deletion (5.1.1(v)): the in-app flow calls `delete-account`, then wipes the local store, Keychain, consent and reminders, and returns to B02. Add a UI test.
8. Network: HTTPS only, no ATS exceptions (I found none), and request timeouts are set. Off-device text inputs are length-limited on the device too.
9. Local data: the store uses file protection that is complete until first user authentication or stronger, and nothing health-derived goes into a shared container.
10. Secrets: confirm no API keys in the repo or the app (only the publishable Supabase key). Run a grep for `sk-ant`, `AIza`, `service_role`, `sb_secret` and `re_` over the full git history and report the result.

## Step 9. App Store readiness check
Run the full unit and UI test suite on the device and on one simulator. Also do the still-open Instruments pass: cold launch, Today scroll, and the Add carousel.

Then report every item as **Verified / Fixed / Blocked (who) / Not checked**:
- crashes;
- onboarding;
- icon and launch screen;
- IAP and restore;
- privacy manifest;
- usage descriptions;
- the consent texts;
- account deletion;
- accessibility (VoiceOver pass on B02–B04 and paywall, AX5);
- offline behaviour (airplane mode on Today, Add, Coach, photo);
- error states;
- minimum iOS 27.0;
- a list of the screenshots that App Store Connect will need.

Don't call anything compliant unless you checked it.

## Report
Send back:
- commits;
- a before/after for the launch time;
- screenshots of B01 (light and dark), B02, B03, B04 and the Home Screen icon (light, dark, tinted);
- the security table (item, finding, severity, fixed or not);
- the readiness table;
- decisions you made;
- questions for Mark.
