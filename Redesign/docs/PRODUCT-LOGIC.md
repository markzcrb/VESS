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
| 13 | VESS+ | StoreKit 2 product | €39.99/year; features listed on E08 |
| 14 | Privacy | On-device processing | Photos processed on device first where possible; export and delete all data available |

## Decided with Mark

### Energy detail (02) status levels

Approved 2026-10-20. Implemented in `StatusLevel` (`Domain/Rules/IntakeAnalysis.swift`), tested in `IntakeAnalysisTests.levels`.

| Row | Measure | Optimal | Sufficient | Low |
|---|---|---|---|---|
| Energy vs. target | kcal ÷ target, prorated by time of day (full target once all main meals are logged) | 90–105 % (the Fuel full-marks band) | above 105 % (being ahead is never "low"), or 63–90 % (energy score ≥ 0.7) | under 63 % |
| Meal regularity | `MealRegularity.score`: closeness of today's meal times to the 14-day median per slot, zero at 2 hours off | ≥ 0.85 | 0.60–0.85 | under 0.60 |
| Before noon | % of the day's kcal logged before 12:00 | no level: shown as a value only | | |
| Whole foods | hidden: there is no food-quality source | | | |

## Already implemented in the codebase (reuse, don't reinvent)
- Nutrition targets: `NutritionTargetCalculator` (Mifflin-St Jeor + activity).
- Day totals: `DaySummary`.
- Hydration contribution %: `Drink` / `HydrationLog`. The defaults live in code (e.g. flat white 79 %). The design copy's "coffee 80 %, tea 90 %" must come from those values, not be hard-coded.
- Food search: `FoodSearch` + `StarterCatalog`.
- Barcode lookup: Open Food Facts.
- Expiration: `ExpirationStatus`.
- Insights: an `Insight` model exists (ruleID, severity, category, dataSource). Map ImpactRow onto it.
