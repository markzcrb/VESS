# UMEVA polish round: camera, flash and focus, plain brand screens, paywall, recipe photos, returning users, splash timing, Anthropic, v1 decisions, UMEVA+ in v1

Branch `redesign`. Never push to `main` or force-push. Make one commit per item and keep the tests green after each one. Don't change the bundle ID or product IDs (Mark decides those separately). Mark found every issue below on his iPhone 17 Pro with the Release build, so check every fix on that phone. If the run destination won't switch, ask Mark to select "Mark's iPhone 17 Pro" in Xcode, then continue.

## 1. Camera opens slowly (Photo › Meal / Menu / Barcode)
Measure first. Add `os_signpost` intervals from the tap on Photo to (a) the sheet becoming visible, (b) `startRunning` returning, and (c) the first preview frame. Do 5 runs before changing anything. Logs: `privacy: .public` for timings only, no user data.

Then make these fixes in order, and measure again after each one:
- Configure and start the `AVCaptureSession` on a dedicated serial session queue, never on main. The sheet animates in right away over a black preview with the mode pill, and the preview fades in on the first frame. Replace the spinner in the screenshot with that.
- **Pre-warm.** When the Add sheet opens, or the Add carousel lands on Photo, build the session on the session queue (input, outputs, preset) but don't start it. Opening then only costs `startRunning`.
- **One session for all three modes.**
  - Keep the metadata output attached, but set `metadataObjectTypes` only in Barcode mode.
  - Never reconfigure the photo output when switching modes.
- **Camera device.** Find it once and cache it (see item 2 for which one). Set focus and exposure after `startRunning`.
- **Closing.** When the sheet closes, stop the session on the background queue. Keep the configured session for 30 s so reopening is instant, then tear it down. Handle interruptions (camera in use, or a phone call as in Mark's screenshots).
- **Permission.** If it isn't determined, ask before building the session. If it's already granted, don't wait on it.

Targets: first frame in under 300 ms on a warm open and under 600 ms on a cold one, with no main-thread hang over 100 ms (Thread Performance Checker on). Add a unit test for the 30 s keep-alive logic.

## 2. Flash doesn't work in Meal, Menu or Barcode; focus is weak
**Flash**
- A flash button in the top corner of the camera frame, in all three modes, 44 pt, with VoiceOver labels "Flash off" / "Flash on" / "Torch on".
- Meal and Menu:
  - Use `AVCapturePhotoSettings.flashMode` (`.off` / `.on` / `.auto`), only when `photoOutput.supportedFlashModes` contains it.
  - The preview shows the torch only when Mark turns on "Torch" (long-press, or a third state; pick one and say which).
- Barcode: the torch (`device.torchMode`, inside `lockForConfiguration`).
- It turns off when the mode changes, the sheet closes, or the app goes to the background. The state is remembered per mode for the session.
- Hide the button if the device has no flash or torch.
- Check that it really lights up on the phone. A UI state alone isn't a fix.

**Focus**
- Use the back virtual device when it exists (`.builtInTripleCamera`, then `.builtInDualWideCamera`, then `.builtInWideAngleCamera`). iOS can then switch to the ultra-wide for close-up macro (food close up, small barcodes).
- Keep the zoom at 1× as the user sees it: set `videoZoomFactor` from `virtualDeviceSwitchOverVideoZoomFactors`, so the preview shows a normal 1× view.
- Use `.continuousAutoFocus` and `.continuousAutoExposure` with `isSubjectAreaChangeMonitoringEnabled` on.
- Barcode mode:
  - Set `autoFocusRangeRestriction = .near` where supported.
  - Raise `videoZoomFactor` so a 20 mm barcode fills the frame at `minimumFocusDistance`, using Apple's AVCamBarcode formula, and cap it at 2×.
  - Set `rectOfInterest` to the guide frame.
- Tap to focus in all modes: a focus and exposure point at the tap (converted through `captureDevicePointConverted`), a small square that fades out, and a return to continuous focus after 3 s or a subject-area change.
- Make sure the photo itself is sharp: `photoQualityPrioritization = .balanced` and the highest supported `maxPhotoDimensions`, then downscale exactly as now before upload.

## 3. Plain brand screens, no silk
Mark doesn't like the silk ("полотно") on the launch, onboarding and welcome screens. Make them plain and minimal. Figma has been updated in the same frames (B01 `239:5536`, B01D `239:5555`, B02 `240:5516`, B03 `240:5554`, B04 `240:5604`).
- **Backgrounds:**
  - B01, B02 and B03: plain `brandPearl` in light mode and `brandGraphite` in dark mode.
  - B04: always `brandGraphite`.
  - No image, no gradient fade, no overlay.
- **Launch to B02 handoff.** The B02 wordmark sits exactly where the launch-screen wordmark is: the same width (192 pt) and the same centre, in the empty area above the content. The splash then fades, and only the text and buttons fade in below. Nothing should jump.
- **Onboarding questions and B03:** the same plain background as the rest of onboarding. No silk on B03's top.
- **Assets:**
  - Remove `silk-pearl` and `silk-graphite` from the asset catalog and from the bundle.
  - Delete `Redesign/Brand/silk-*.png`.
  - Report the bundle size before and after.
- The app icon stays as it is (Λ on silk). Mark only asked about the screens.
- Update the B01–B04 captures in `Redesign/Captures/release/`.

## 4. Paywall: the plan cards are uneven (screenshot 1)
- **Badge.** "−48 %" wraps onto two lines. Make it "−48%" with no space, on one line (`fixedSize`), as a small pill to the right of "ANNUAL" on the same baseline. At AX sizes it moves under the label and is never cut.
- **Cards.**
  - The two cards have the same height (the taller one sets it) and the same top padding.
  - The same order in each: label row, then price, then period line ("a year · 4,17 € a month" / "a month").
  - The prices are the same size and weight in both cards.
  - The selected card shows the border and a check, and the other card's text isn't greyed out.
- **Bottom bar.** The cards must be fully visible above the pinned bottom bar (CTA plus legal text) at the default size. Reserve the bar's height as bottom content inset, so the cards are never cut, as they are in the screenshot.
- **Grid.** Consistent spacing everywhere: 16 pt side margins, 12 pt between the cards, and an 8 pt grid inside.
- Check the light, dark and AX5 layouts. Add a snapshot or UI test showing both cards fully visible at the default size.

## 5. Plan › recipe opens without its photo (screenshot 5)
A recipe opened from Plan shows the placeholder (fork and knife) instead of its photo. The same recipe from Recipes shows the photo. Find why; it's likely that the Plan entry stores a copy or an id that doesn't resolve to the catalog photo, or that the user's AI recipe photo path isn't passed.
- Fix it so every entry point (Plan, Today meal, Recipes, Saved, AI Chef) uses one shared photo lookup.
- Add a unit test: a planned catalog recipe and a planned user recipe both resolve to their photo.
- Use the placeholder only when the recipe truly has no photo.

## 6. "I already use UMEVA" runs onboarding again
The log and profile live only on the iPhone, so after a new install nothing comes back from the server. A returning user still shouldn't have to answer all 7 questions again.
- **Same device, profile still there** (for example, signed out): sign in and go straight to Today. Never show onboarding again.
- **New install:**
  - Mirror the profile in iCloud key-value storage (`NSUbiquitousKeyValueStore`). That's goal, sex, birth year, height, weight, activity, diet, allergens, avoid list, targets and units: small, and Apple's iCloud, not our server.
  - Write it whenever the profile changes. After sign-in, if a profile exists, show "Welcome back, {name}" with the restored targets (B03 layout, title "WELCOME BACK"), then Today.
  - This needs the iCloud capability. Add it behind a build flag, and say in the report whether the current team can sign it. If it can't, the app must still build and fall back as below.
  - Say in `APP-STORE-PRIVACY.md` that the profile is in the user's iCloud when iCloud is on.
- **Nothing to restore:**
  - Show one short screen: "Nothing to restore on this iPhone. Your log stays on the iPhone it was made on." Offer "Restore from Apple Health" and "Set up again".
  - Restore from Apple Health reads sex, date of birth, height and the latest weight from Health, with permission, and pre-fills those questions.
  - Then ask only what Health doesn't have (goal, activity, diet and allergies), shown as one compact screen, not 7 steps.
- Add UI tests for each of the three paths. Onboarding must never start after a successful restore.

## 7. The splash flashes by too fast
At cold launch the store is ready in about 60 ms, so the splash disappears almost at once and reads as a flicker.
- Cold launch only: keep the wordmark on screen for at least **900 ms** from the first frame, or longer if the store isn't ready.
- Then a calm **500 ms** crossfade, ease-in-out. The wordmark stays in place, as described in item 3, and the content of the next screen fades in under it.
- With Reduce Motion: the same 900 ms hold, then a 250 ms opacity fade.
- Warm resume from the background shows no splash at all.
- Never hold longer than 1.5 s. Launch is still measured from the first frame, so the numbers from the last round stay comparable. Report both: the first frame, and "interactive", meaning when the content becomes tappable.

## 8. Switch the app's AI disclosure to Anthropic (Claude Haiku 5.5)
Mark wants the AI to be Anthropic Claude Haiku 5.5. The server already defaults to `claude-haiku-5-5`. The server switch is Mark's step: he adds the `ANTHROPIC_API_KEY` secret and sets `AI_PROVIDER=anthropic` in Supabase.
- Set `AIProcessor` to Anthropic: "Anthropic Claude" / "Anthropic".
- Bump the consent version for **all** AI features (Coach, photo/menu, Chef), so everyone is asked again with the new processor named.
- Update `APP-STORE-PRIVACY.md`, the policy draft and the review notes to say Anthropic (Claude API).
- Don't add any fallback to another provider in the app.
- **Verification on the phone, after Mark has set the secrets:**
  - Ask one Coach question, take one photo estimate, and create one Chef recipe. All three must succeed.
  - Mark then checks the Anthropic Console › Usage for requests to `claude-haiku-5-5` at that time. That's the proof it's Haiku.
  - If any of them answers "AI is busy", the key or the model is missing. Report it, and don't work around it.

## 9. Mark's decisions from this round
- **iPhone only.** Mac ("Designed for iPhone") and Vision Pro are off. Note in the report that Mark unticks both in App Store Connect.
- **Bundle ID `app.umeva.ios`.**
  - Product IDs `app.umeva.ios.plus.monthly` (7,99 €) and `app.umeva.ios.plus.annual` (49,99 €, 7-day free trial). Update the `.storekit` files, including the test copy.
  - The test target becomes `app.umeva.ios.tests`.
  - Logger subsystem follows the bundle ID automatically.
  - Check that HealthKit and the Keychain still work after a clean install. The old keychain items under the old ID are gone, so Mark signs in once again.
  - List in the report what has to change outside Xcode: the Supabase Apple provider Client ID, and the App Store Connect app record.

## 10. UMEVA+ ships in v1: paywall in Release and server-verified plans
Mark wants the paid plan in the first release.

**Server side (already written by the backend; don't change it)**
- First delete `supabase/migrations/20261029000000_ai_free_limits_v1_and_testers.sql`: it's superseded by the plans migration below.
- The migration `supabase/migrations/20261029000000_plans_subscriptions_testers.sql` adds the `subscriptions` table and per-plan limits. Free is Coach 3 / photo and menu 1 / Chef 1 a day; UMEVA+ is 15 / 10 / 5; tester accounts get 50 / 30 / 30. It is written but not applied yet: Mark approves applying it.
- New edge function **`entitlement`** (JWT required): `POST { signed_transactions: [jws…] }` returns `{ plan: "free"|"plus"|"tester", product_id, expires_at, limits: { coach, photo, chef }, rejected: [{reason}] }`.
  - It verifies Apple's signature and certificate chain using Apple's App Store Server Library.
  - It checks the bundle and product IDs, and that the purchase belongs to this account (`appAccountToken`). A purchase recorded for another account is refused.
  - Xcode StoreKit-test transactions are accepted only for tester accounts.
- New edge function **`appstore-notifications`** (no JWT; Apple calls it): App Store Server Notifications V2 for renewals, expiry, refunds and revocations.
- Limits always come from the server. The app never decides a plan by itself.

**App side**
1. Remove the DEBUG-only gating. The paywall, the purchase code and B04 are in Release.
2. Every purchase: `product.purchase(options: [.appAccountToken(userID)])`, where `userID` is the signed-in Supabase user's UUID. Buying needs an account: signed out, the paywall's button first opens sign-in, then continues the purchase.
3. After a verified purchase, on every launch (signed in), on `Transaction.updates` and after Restore:
   - Collect `jwsRepresentation` of every verified `Transaction.currentEntitlements` item for the two product IDs, and POST them to `entitlement`.
   - Store the response (plan, expiry, limits) as the single source of truth for what the app shows: limits, the UMEVA+ badge and the "N left today" counters.
   - Replace the hard-coded `UMEVAPlusLimits` with these server limits. Keep the constant only as an offline display fallback, labelled as such.
4. If StoreKit shows a valid purchase but the server answers `free` (a `rejected` reason, or the call fails):
   - Show "UMEVA+ is active. Updating your limits…" and retry with backoff (2 s, 10 s, 60 s, then on next launch).
   - Never show an error that blames the user. Log only the reason code.
   - If the reason is `other_account`, say: "This UMEVA+ purchase belongs to another UMEVA account. Sign in with that account, or contact support."
5. Limit reached:
   - Free users see the limit message with "Get UMEVA+".
   - Plus users see "You've used today's {n}. Resets at {time}."
6. B04 shows after a verified purchase and after the server confirms `plus` (show "Activating…" until then, at most 5 s, then show B04 anyway with the limits loading).
7. The paywall links Terms and Privacy to `umeva.app/terms` and `umeva.app/privacy`. Keep Apple's standard EULA linked from the terms page; Mark publishes the pages.
8. Tests:
   - unit tests for the entitlement response mapping and the retry and backoff logic;
   - StoreKit tests on the local `.storekit` for purchase, trial, renewal, refund, expiry and Ask to Buy;
   - a UI test showing that a signed-out purchase asks for sign-in first.

   The server calls in tests use a mock. Real Sandbox purchases need Mark's paid developer account and the products in App Store Connect, so report that as blocked if it's still missing.
9. Update `Redesign/docs/APP-STORE-PRIVACY.md`. Purchases add the Purchases › Purchase History data type (linked to the user, App Functionality), because the subscription's transaction ID and expiry are stored with the account.
10. Review notes: describe the free versus UMEVA+ limits and how a reviewer can test (sandbox account). Mention that AI features need sign-in.

## Report
- commits;
- the UMEVA+ flow on the phone: purchase in Xcode StoreKit testing, then the `entitlement` response, then the limits shown in Coach, photo and Chef;
- camera timings before and after (warm and cold);
- whether the flash and torch actually fire on the phone;
- focus results: a barcode at 10 cm and a plate photo, with an example of each;
- the paywall at default size and AX5;
- B01–B04 captures;
- recipe photo test;
- the three returning-user paths;
- bundle size before and after;
- the splash timings (first frame and interactive);
- the AI verification results (Coach, photo, Chef);
- the new bundle ID checks;
- anything blocked.
