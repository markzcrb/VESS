# Task: Recipes tab, Health screens and nutrition preferences

Mark approved the designs in `Redesign/Design/screens/` R01–R07, H00–H04 and P01 (see `Redesign/docs/SCREENS.md`, section O). This task builds them for real. `CLAUDE.md` and `VESS_ARCHITECTURE.md` still apply in full (tokens only, local-first, deterministic domain rules, no third-party packages, MainActor default, tests green). Work on the `redesign` branch, commit per step below, never push to `main`, never force-push.

## What you get (already in the repo)

| Path | What it is |
|---|---|
| `Redesign/docs/RECIPES.md` | The 122 Discover recipes as a readable table. |
| `Redesign/Data/recipes.json` | **The data to ship.** 122 recipes: ingredients with display amount + unit, `grams`, pantry `key`, EU-14 `allergens`, USDA source; steps; servings; minutes; diet tags; `nutritionPerServing` (calculated from USDA SR Legacy); `highProtein`; `contains` flags; `photo` id. |
| `Redesign/Data/usda-sr-legacy.json` | Compact USDA SR Legacy table (8 422 generic foods, per 100 g: kcal, protein, carbs, fat, fiber, sugar, sodium, saturated fat, plus up to two household portions). Public domain. On-device source for "Generic · USDA" ingredient search and for recalculating any recipe. |
| `Redesign/RecipePhotos/` | 122 JPGs named `<recipe id>.jpg` (Mark exports them from Figma, 1200 × 896). If the folder is missing or incomplete, build everything anyway with the quiet placeholder tile and list the missing ids. |
| `supabase/functions/chef/` | New edge function `chef`, already deployed. Contract below. |
| `supabase/migrations/20261024000000_ai_chef_quota.sql` | Chef quota (10 per day), already applied. |

## Resolved decisions (don't ask again)

- **Recipe photos:** Mark supplied them. This resolves the "Food photography" conflict in `CLAUDE.md`; update that bullet. User recipes use the user's own photo, otherwise the quiet tile.
- **Data sources:** generic foods = bundled USDA SR Legacy; branded products = Open Food Facts (existing `OpenFoodFactsClient`). Settings › About gets a "Data sources" row: "Generic foods: USDA FoodData Central (public domain). Products: Open Food Facts, ODbL." (OFF attribution is required.)
- **AI never supplies nutrition.** Every AI recipe is recalculated on device from USDA/OFF data.
- **No prices.** R05 shows "≈ €7.80" for missing items; we have no price source. Drop it.

## Step 1 · Inventory (stop and show Mark)

Short tables: each screen R01–R07, H00–H04, P01 → existing file or NEW; models that change; HealthKit types to add; anything in the designs this brief doesn't cover. Then wait for Mark.

## Step 2 · Models and data

1. **Allergen → EU 14.** Replace the 5-case `Allergen` with the 14 EU allergens: `gluten, crustaceans, eggs, fish, peanuts, soy, milk, nuts, celery, mustard, sesame, sulphites, lupin, molluscs` (P01 labels: Wheat / gluten, Shellfish = crustaceans, Tree nuts = nuts). Decoding must stay backward compatible: old raw value `lactose` decodes as `.milk`. Add a test that decodes an old `UserProfile` JSON.
2. **Nutrition preferences (P01).** One diet: `noRestrictions, pescatarian, vegetarian, vegan, flexitarian`. Also prefer (any): `highProtein, lowerCarb, mediterranean, glutenFree, dairyFree, halal, kosher`. Allergies (EU 14). Ingredients you don't eat (free text list, normalised). `showNonFittingRecipes: Bool` (default off). Usual meal times (3 times). Migrate the existing `DietaryPreference` / `otherRestrictions` into these without losing anything (vegetarian → vegetarian, vegan → vegan, highProtein → noRestrictions + highProtein, lowCarb → lowerCarb, custom text → ingredients you don't eat only if it's a single ingredient, otherwise keep it in `customDietDescription`). P01 replaces E03.
3. **Recipe.** Extend the existing `Recipe` (keep the type) to match `recipes.json`: `RecipeCategory` (`breakfast, lunch, dinner, snack, smoothie, dessert`; plan/log slot: smoothie and dessert default to `.snack`, user can pick), `extraTime`, ingredients with `key`, `grams`, `allergens`, `source` (USDA id / OFF barcode / label / user), steps, `tip`, `diet`, `highProtein`, `contains`, `photo`, `origin` (`discover`, `user`, `ai`). Discover recipes load once from the bundled JSON (`RecipeCatalog`, read off the main thread, cached). User and saved AI recipes are SwiftData records (local only, never synced). Remove `MockData.recipes` from DEBUG once the catalog works.
4. **Photos.** Convert `Redesign/RecipePhotos/*.jpg` into `Assets.xcassets/RecipePhotos/<id>.imageset` (one 1x-universal JPEG, ≤ 300 KB: `sips -Z 1200 -s format jpeg -s formatOptions 70`). Check the total added size and report it.
5. **USDA table.** Add `usda-sr-legacy.json` to the app bundle. `GenericFoodDatabase` loads it lazily off the main thread and offers prefix/word search ranked by: all query words present, shorter description first, raw/plain forms first. Expose household portions as units.

## Step 3 · Domain rules (pure, tested)

**RecipeNutritionCalculator.** `perServing = Σ(per100 × grams / 100) / servings`. Unknown fiber/sugar/sodium on any ingredient → that value is unknown in the total (never 0), same convention as `NutritionFacts`. Test: for every Discover recipe the calculator reproduces `nutritionPerServing` within ±1 kcal / ±0.1 g. HP rule (same as the data): protein ≥ 20 g per serving, or ≥ 15 g and ≥ 30 % of energy.

**RecipeFit** (one function used by Discover, AI Chef, Plan suggestions):
1. *Allergens* — hard filter everywhere, including when "Show recipes that don't fit" is on. Never shown.
2. *Diet* — vegan: `VG` tag; vegetarian: `V` or `VG`; pescatarian: no `meat` or `poultry` in `contains`; flexitarian and no restrictions: no filter. Halal: no `pork`, no `alcohol`. Kosher: no `pork`, no `shellfish`, no `molluscs`, not (`meat`/`poultry` with `dairy`). Halal/Kosher are ingredient-based, not certification: say so in the P01 footnote.
3. *Ingredients you don't eat* — match against ingredient `key` and `name`, case- and diacritic-insensitive, whole words, simple plural (`mushroom` hides "Mushrooms"). Hidden in Discover; still openable from search with a tag "Contains mushrooms".
4. Diet and don't-eat failures are hidden unless "Show recipes that don't fit" is on; then they show greyed with the reason ("Has chicken", "Contains mushrooms"). The "N hidden" note on R01 counts them.
5. *Also prefer* chips are ranking boosts, not filters: high-protein (`highProtein`), lower-carb (≤ 30 g carbs per serving), gluten-free (`GF`), dairy-free (`DF`), mediterranean (`mediterranean` in `contains`/tags), flexitarian (vegetarian recipes first).

**Discover (R01).** Search over name and ingredient names. Meal chips: All, Breakfast, Lunch, Dinner, Snacks, Smoothies, Desserts. Collections: Vegan, Vegetarian, Fish and seafood, Gluten-free, Dairy-free, High-protein, Under 20 min; each collection respects RecipeFit and hides when empty. Featured card: the best fit for the next meal slot by time of day (from usual meal times), rotating daily (stable seed = day).

**AI Chef ranking (R05).** Candidates: Discover + My recipes that pass RecipeFit (don't-eat items are never used, even with the toggle on). Pantry matching: an ingredient is "at home" if a pantry item's normalised name matches the ingredient `key` or name (same matcher as above); salt, pepper, water and `optional` ingredients don't count either way. Score, in order: (1) number of use-soon items used (`ExpirationStatus`, 3-day threshold), (2) share of ingredients at home, (3) fit to today's remaining protein/energy (closer to the remaining protein without exceeding remaining energy). Show "N of M at home · uses K use-soon", the have / missing block, and "Add missing to grocery". "Swap X for Y" only from a small explicit table (cod ↔ salmon ↔ tofu, chicken breast ↔ turkey breast ↔ tofu, Greek yogurt ↔ skyr, milk ↔ soy drink), and only when the swap passes RecipeFit and the swap item is at home. Filter chips: meal, Under 30 min, High-protein, Uses use-soon.

## Step 4 · Screens

Build R01, R02, R03, R04, R05, R06, R07, then P01, matching the PNGs (process in `CLAUDE.md` › Workflow step 4). Notes:
- Recipe detail: reuse the existing recipe detail layout (screen 08 / `RecipeView`) with the photo header; servings stepper scales amounts and nutrition; "Add to plan" and "Log" use one serving by default.
- R03 editor: nutrition per serving is live from the calculator; diet tags and allergens are derived from ingredients (user can't untick an allergen that an ingredient has). Ingredient source line shows "USDA", "Open Food Facts" or "Your pantry".
- R04: source chips All / Generic · USDA / Brands · OFF / My pantry. Amount stepper + units (g, ml, household portions from USDA, piece where the food has one).
- Empty states: no pantry items (AI Chef explains and links to Pantry), no matches, no My recipes, search with no results.

## Step 5 · Create with AI (R06 → R07)

- Gated by the existing AI consent (`AIConsentSheet`) and sign-in, like Coach. The "what is sent" line on R06 must stay true: only the fields below.
- `POST /functions/v1/chef` with the user's JWT and `apikey`, body:
  `{ pantry: [{name, use_soon}], must_use: [name], meal: "breakfast|lunch|dinner|snack", goal: "high_protein|lighter|quick|comfort|none", servings: 1–8, only_what_i_have: Bool, diet: "<diet + prefs in plain words>", avoid: [don't-eat items], allergens: [EU-14 raw values], protein_gap_g: Number?, locale }`
  → `200 { recipe: { name, minutes, servings, ingredients: [{name, amount, unit, grams, from_pantry, usda_hint}], steps: [String], tip }, remaining, estimated: true }`. Errors as Coach: `401`, `429 daily_limit` ("No AI recipes left today. Back tomorrow."), `502 upstream` (quota refunded), `503 not_configured`.
- On device, before showing R07: match each ingredient to `GenericFoodDatabase` using `usda_hint` first, then `name`; pantry items with known nutrition win. Unmatched ingredients show "No nutrition data · Choose food" and the total says "Partial". Recalculate nutrition with the calculator.
- **Allergen and don't-eat re-check on device** (the model can be wrong): derive allergens from the matched USDA food and a keyword table (e.g. soy sauce → soy + gluten, pesto → nuts + milk, mayonnaise → eggs, prawn/shrimp → crustaceans, mussel/squid/clam → molluscs, tahini → sesame, wine → sulphites, stock cube → celery). If anything conflicts with the user's allergens or don't-eat list, don't show the draft: "That draft used something you avoid. Try another." and refund nothing (it was a real call).
- R07 is a draft until Save; Discard deletes it. Saved AI recipes are `origin: .ai` and keep an "AI" tag.

## Step 6 · Health (H00–H04)

HealthKit read-only (add types to the existing authorisation, explain in the purpose string). Nothing leaves the phone.
- **Sleep (H01):** `sleepAnalysis` with stages (core, deep, REM, awake, in bed). "Last night" = the main sleep session ending between 03:00 and 14:00 today (merge samples from all sources, prefer Apple Watch for overlaps). Ring = time asleep vs sleep target (default 8 h, editable on the screen). Stages bar and rows only when stage data exists, else "Stages need Apple Watch". 7 nights list.
- **Heart (H02):** `restingHeartRate`, `heartRateVariabilitySDNN`, `walkingHeartRateAverage`, `heartRate` (hourly min–max for today). Ring = today's resting HR within the user's 30-day range (not a score). 7 days.
- **Stress estimate (H03):** baseline = median of the last 28 days of overnight HRV (SDNN) and resting HR; needs ≥ 14 days, else "Building your baseline · N of 14 days". Today: HRV ≥ 15 % below baseline AND resting HR ≥ 5 % above → Elevated; HRV ≥ 30 % below AND resting HR ≥ 10 % above → High; otherwise Calm. Parts of day from daytime HRV samples where present. State of Mind check-in writes nothing to Health in this task; read `HKStateOfMind` if present and show it as a signal. Always labelled "Estimate, not a medical measurement". Ring colour `metric/water`, never red.
- **Body (H04):** BMI = kg / m² from the profile height and latest weight (Health weight wins if newer). WHO adult ranges. Hidden under 18 and when pregnancy is set; the honest note from the PNG stays. 12-week trend from `weights`.
- **H00 hub:** tiles with last value and "Connect Apple Health" when not authorised; entry from You › Health and the Today metric strip.
- New tokens `metric/sleep`, `metric/heart` (values in SCREENS.md) go into `VESSColor` and Assets with Light values.
- Update `Redesign/docs/APP-STORE-PRIVACY.md` for the new Health types (read only, on device).

## Tests (add to `VESSTests`)

Allergen legacy decoding · preference migration · calculator reproduces all 122 recipes · RecipeFit (allergen hard filter with toggle on, pescatarian, vegan, halal/kosher, don't-eat plural matching) · AI Chef ranking order on a fixed pantry · AI draft re-check rejects soy sauce for a soy-allergic user · stress classification table · sleep session selection · BMI hidden under 18.

## Report back

Per step: files changed, screenshots vs reference, open questions, anything stubbed. Stop after Step 1 for Mark's go-ahead.
