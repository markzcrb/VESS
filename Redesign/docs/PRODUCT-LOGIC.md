# Behaviour the design does not define

The screens show these features, but their logic is not specified. **Do not invent formulas silently.** Use stubs with the demo values from `DATA.md`, and ask Mark to confirm each item before implementing it for real.

| # | Feature | Open question | Suggested default (proposal only) |
|---|---|---|---|
| 1 | **Fuel score (0–100)** | What it is made of, and the weights | 40 % energy vs target (peaks at 90–105 %), 30 % protein vs target, 20 % hydration vs target, 10 % meal timing regularity; prorated by time of day. Shows "—" before the first log. |
| 2 | Energy detail rows | Definitions of "meal regularity", "before noon", "whole foods" | Regularity = deviation from usual meal times; before noon = % of kcal before 12:00; whole foods = share of items not ultra-processed (needs a food-quality source; hide the row if there isn't one) |
| 3 | **Insights (impact)** | Statistical method | Compare Fuel on days with vs without each tag over 90 days; require 30+ logged days and at least 5 days per side; show as % difference; label as patterns, not causes |
| 4 | **Coach** | Backend, model, data access, guardrails | LLM with read-only access to the user's logs; never medical advice; can propose plan swaps that need confirmation; disclaimer "Coach can make mistakes." |
| 5 | Photo estimate | Recognition provider | Vision model returns items + portion estimates; the user confirms every item; entries are marked "Estimated" |
| 6 | Barcode | Product database | **Already in code:** `OpenFoodFactsClient` + `FoodLookupService`. Camera scanning (VisionKit) is deferred per the architecture doc; "not found" leads to manual entry |
| 7 | Apple Health | Read/write scopes | Read steps, workouts, active energy, weight, heart rate. Write nutrition, water, caffeine (toggles in E05). Steps are never estimated. |
| 8 | Entered workout kcal | Formula | MET × kg × hours, shown as "≈" and labelled an estimate |
| 9 | Plan suggestions | Ranking rules | Fill open slots; respect diet (pescatarian, nut-free); prefer pantry items that expire soon; hit the protein target |
| 10 | Grocery list | Generation | From planned meals minus pantry stock; grouped by aisle or by meal; "Done shopping" moves checked items to Pantry |
| 11 | Pantry expiry | Defaults | **Already in code:** `InventoryItem` + `ExpirationStatus` (3-day threshold). Reuse them |
| 12 | Notifications | Rules | Meal reminder only if nothing is logged by the usual time; quiet hours 22:00–07:00 |
| 13 | VESS+ | StoreKit 2 products | Monthly 7,99 €/month; Annual 49,99 €/year with a 7-day free trial (annual only); limits below |
| 14 | Privacy | On-device processing | Photos processed on device first where possible; export and delete all data available |

## Decided with Mark

### Fuel score (#1), revised 2026-10-20

Scored against full-day targets, the same measure as the metric strip; no clock proration and no "all main meals" switch. 40 % energy (linear to full marks at 100 %, full to 105 %, then a gentle linear decline to zero at 205 %), 30 % protein and 20 % hydration (up to the target), 10 % regularity (`MealRegularity.dayProgress`: each meal slot with a usual time adds its share when logged, so it never falls). The score only rises as the user logs; overshooting energy is the only way it falls. The ring caption reads "Building" until breakfast, lunch and dinner are logged, then "Main meals logged". Tested in `FuelScoreTests` and `FuelTimelineTests`.

### Energy detail (02) status levels

Approved 2026-10-20. Implemented in `StatusLevel` (`Domain/Rules/IntakeAnalysis.swift`), tested in `IntakeAnalysisTests.levels`.

| Row | Measure | Optimal | Sufficient | Low |
|---|---|---|---|---|
| Energy vs. target | kcal ÷ target, prorated by time of day (full target once all main meals are logged) | 90–105 % (its own band; no longer shared with Fuel) | above 105 % (being ahead is never "low"), or 63–90 % | under 63 % |
| Meal regularity | `MealRegularity.score`: closeness of today's meal times to the 14-day median per slot, zero at 2 hours off | ≥ 0.85 | 0.60–0.85 | under 0.60 |
| Before noon | % of the day's kcal logged before 12:00 | no level: shown as a value only | | |
| Whole foods | hidden: there is no food-quality source | | | |

### Activity (#7, #8 and comparisons), decided 2026-10-21

- **Apple Health (#7):** read-only: steps, workouts, active energy, weight. No heart rate, day distance, flights or walking time; those design rows are left out. A workout shows a distance only if the workout itself recorded one. Permission is asked from Activity ("Connect Apple Health"), never in onboarding. Health never says whether read access was granted, so if nothing at all comes back VESS shows "—" and how to allow access. Steps are never estimated. `HealthKitService` (`Services/HealthKit/`), `HealthDataStore`.
- **Entered workout energy (#8):** MET × body weight (kg) × hours, with a fixed MET per type and effort from the Compendium of Physical Activities (`WorkoutEnergy`), always shown with "≈" and labelled an estimate. The estimate is stored with the workout when it's saved. Demo values therefore differ from the PNGs: 30 min moderate walk 137 (PNG 150), Sunday's cycle 551 (520), Monday's strength 353 (210).
- **Comparisons:** "a typical Tuesday" is the median of the last four same weekdays, each up to the same clock time (the last sync); it needs all four. Within ±10 % is about the same (dot), otherwise ▲ / ▼. Week against the week before and 30 days against the 30 before, only when the earlier period has data on every day. The weekend/quietest-day pattern needs four full weeks. Nothing causal: the "20-minute walk adds 2,300 steps" line is dropped; the card states today against typical. Everything is hidden without enough data. `ActivityTrends`, tested in `ActivityTrendsTests`.
- **Storage:** entered workouts in `StoredWorkout` (additive, payload pattern), deletable on the workout screen. Recorded workouts stay in Apple Health. Step goal: `UserProfile.stepsTarget`, 8,000 when unset.

### You (11, E01–E10), decided 2026-10-21

- **Notifications (#12):** on-device and opt-in. One reminder per main meal, 30 minutes after its usual time (`usualTime`, three days of history), only if nothing is logged for it that day, never between 22:00 and 07:00. Planned 7 days ahead and re-planned on launch, on return to the app and whenever today's log changes. Permission is asked when the first reminder is turned on. Supplement reminders (E04) repeat daily at the time the user sets. `MealReminders`, `ReminderService`; tested in `MealRemindersTests`. Water nudges, expiring food, weekly plan and insight notifications are not built.
- **Apple Health (E05):** read-only status. The four types as plain rows, last sync, and how to change access in the Health app. No write section, no heart rate. Permission text approved: "VESS reads your steps, workouts, active energy and weight to show them in Activity and Today. It never writes to Apple Health, and this data stays on your iPhone."
- **Privacy (#14, E07):** a plain statement of what is stored where, "Export my data" (one JSON document, ISO 8601 dates, via the share sheet; `LocalStore.exportData`) and Delete all data. No photo or analytics switches until those features exist.
- **VESS+ (#13, E08):** DEBUG-only screen built on StoreKit 2; no row on You in Release until the products exist. Prices shown are `Product.displayPrice`; the euro values are DEBUG fallbacks.

### VESS+ plans and limits (proposal, not live)

Plans: Monthly 7,99 €/month; Annual 49,99 €/year ("4,17 €/month · save 48 %"), 7-day free trial on the annual plan only. Product IDs use the bundle ID as prefix: `<bundle id>.plus.monthly` and `<bundle id>.plus.annual` (today `com.markgerasimovpersonalteam.VESS.plus.monthly` / `.plus.annual`). Both sit in one subscription group, "VESS+"; the annual plan has a 1-week free introductory offer. `VESS.storekit` (repo root, set in the VESS scheme's Run options) mirrors them for local testing.

| Feature | Free | VESS+ |
|---|---|---|
| AI Coach questions | 3 a day | 15 a day |
| Meal photo estimates | 1 a day | 10 a day |
| AI Chef recipes | 1 a day | 5 a day |
| Insights history | 30 days | All |
| Health patterns | — | ✓ |

Logging, recipes, pantry, grocery and Apple Health stay free. The server limits (`ai_daily_limit`) are **not** changed yet: today they are Coach 20, photos 10, AI Chef 10 for everyone. They switch to the table above when subscriptions ship (Mark changes the server).
- **Targets (E01):** VESS never changes targets on its own. Goals shows the `NutritionTargetCalculator` suggestion for the current body and direction, applied only after confirmation.
- **Weight (11):** the latest Apple Health weight, or the profile's, and the change over 12 weeks. No "steady" verdict and no target range: those rules aren't defined.
- **Contrast:** the optimal green as text (tags, kickers) uses `statusOptimalText`, Light #1B7349 (4.6:1 on its tint), Dark unchanged.

## Already implemented in the codebase (reuse, don't reinvent)
- Nutrition targets: `NutritionTargetCalculator` (Mifflin-St Jeor + activity).
- Day totals: `DaySummary`.
- Hydration contribution %: `Drink` / `HydrationLog`. The defaults live in code (e.g. flat white 79 %). The design copy's "coffee 80 %, tea 90 %" must come from those values, not be hard-coded.
- Food search: `FoodSearch` + `StarterCatalog`.
- Barcode lookup: Open Food Facts.
- Expiration: `ExpirationStatus`.
- Insights: an `Insight` model exists (ruleID, severity, category, dataSource). Map ImpactRow onto it.

## Menu scan (M01–M03)

Photo › Menu sends one photo to `/functions/v1/menu` (one photo estimate). Everything after that is decided on the device (`MenuRules`), and the result is kept only while the Add sheet is open.

| Rule | Value |
|---|---|
| Doesn't fit | A confirmed allergen of the user's; the diet, halal or kosher read from `contains` (same rule as recipes, `RecipeFit`); a don't-eat item in the dish name or its ingredients. Listed under "Doesn't fit you · N", folded until Show. |
| Ask (maybe) | The dish fits but is a kind that often has one of the user's allergens without it being listed: "Ask: often has walnuts". Keyword table in `MenuRules.hintWords` (beet salad → walnuts, pesto, satay, caesar, paella, risotto…). |
| Best for you | Fitting dishes; low confidence last, then within the energy left before above it, then closest to the protein left. |
| High-protein | The recipe high-protein rule: ≥ 20 g, or ≥ 15 g at ≥ 30 % of energy. |
| Lighter | 500 kcal or less per regular portion. |
| Tags | Fits today (· Best protein for the most protein within the energy left), Above energy left, Low protein (< 15 g), Fits today · rough estimate (low confidence). |
| Portion | Smaller ×0.75, Regular, Larger ×1.25. The portion picked in the dish sheet is kept for that dish in the list and the add bar. |
| Meal | From the time of day (`MealType.likely`); touch and hold Add to pick another. |
| Logged | One entry per dish, source photo estimate, with the menu's name ("… · The evening menu · Estimated" in the diary). |
