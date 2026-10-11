# VESS — Architecture

> Your body. Better understood.
> Complexity underneath. Simplicity on top.

This document is the technical source of truth for VESS. It records decisions
already made (Phase 0) and the shape of decisions coming in later phases.
Anything marked **Planned** does not exist in code yet.

---

## 1. Principles

1. **Local first.** Every tracking action (food, water, workouts, weight,
   inventory) completes on device, offline, with no network or AI call.
   The cloud is for sync and for features that truly need it.
2. **Deterministic truth.** Calories, macros, BMI, targets, hydration and
   expiration are pure Swift calculations with unit tests. AI may *describe*
   or *estimate*, but is never the source of truth for a number we can compute.
3. **Domain owns the rules.** Views render state. Business rules live in plain
   value types with no SwiftUI, network or persistence dependency.
4. **Native first.** SwiftUI, Swift Concurrency, SwiftData, HealthKit,
   StoreKit 2, UserNotifications. Third-party code only with a written reason.
5. **No speculative abstraction.** A protocol is introduced in the phase that
   first needs a second implementation (real vs. mock/preview), not before.
6. **Privacy is a feature.** Minimum data, no health data for advertising,
   explicit consent per capability, deletable account.

---

## 2. Layers

```
┌──────────────────────────────────────────────────────────┐
│ Features (SwiftUI Views)                                 │  render, user intent
├──────────────────────────────────────────────────────────┤
│ Presentation (@Observable models, one per screen)        │  screen state, formatting
├──────────────────────────────────────────────────────────┤
│ Domain (value types + pure rules)                        │  models, calculations
├──────────────────────────────────────────────────────────┤
│ Data (repositories)          │ Services (system/cloud)   │  storage, sync, HealthKit,
│ SwiftData · Supabase sync    │ HealthKit · StoreKit · …  │  notifications, AI, billing
└──────────────────────────────────────────────────────────┘
```

Dependencies point **down only**. Views never talk to Supabase, HealthKit or
StoreKit directly; they talk to a screen model, which talks to repositories
and services injected through the SwiftUI environment.

### Concurrency

The app target uses Xcode's default **MainActor isolation** with approachable
concurrency. UI and presentation code is therefore main-actor by default.
Domain and mock data types (and their extensions) are explicitly
`nonisolated`, `Sendable` value types, so they can be computed off the main
actor and used freely in tests. Repositories and services that do I/O will be
`actor`s or `nonisolated` types with `async` APIs. Combine is not used.

---

## 3. Folder structure

```
Untitled Project/                     (repo root; rename planned, see README)
├── VESS_ARCHITECTURE.md
├── README.md
├── MyApp/                            app target (file-system synchronized)
│   ├── App/
│   │   ├── VESSApp.swift             @main entry point
│   │   └── RootTabView.swift         five-tab shell, AppTab
│   ├── Core/
│   │   └── DesignSystem/
│   │       ├── Tokens/               VESSColor, VESSTypography, VESSLayout
│   │       ├── Components/           buttons, card, text field, chip,
│   │       │                         progress bar, screen + section header
│   │       └── DesignSystemGallery   DEBUG-only preview of everything
│   ├── Domain/
│   │   └── Models/                   all domain models + pure rules
│   ├── Data/
│   │   └── Mock/MockData.swift       realistic dataset for previews/tests
│   ├── Features/
│   │   ├── Today/  Nutrition/  Plan/  Activity/  Profile/
│   └── Assets.xcassets               Colors/ (semantic light/dark), AccentColor
└── VESSTests/                        Swift Testing unit tests
```

**Planned additions** (each created by the phase that first needs it):

| Folder | Phase | Contents |
|---|---|---|
| `Domain/Rules/` | 1 | `NutritionTargetCalculator` (Mifflin-St Jeor + activity factor) |
| `Data/Repositories/` | 1 | repository protocols + SwiftData implementations |
| `Data/Local/` | 1 | SwiftData `@Model` persistence types and mapping |
| `Core/Environment/` | 1 | `AppDependencies` container injected via `@Environment` |
| `Features/Onboarding/` | 1 | progressive onboarding flow |
| `Domain/Insights/` | 6 | rule protocol and rule implementations |
| `Services/HealthKit/` | 7 | `HealthService` |
| `Data/Remote/` | 7+ | Supabase client, DTOs, sync engine |
| `Services/AI/` | 8 | `AIService` |
| `Services/Subscriptions/` | 9 | `SubscriptionService` (StoreKit 2) |
| `VESSUITests/` | 1 | XCUIAutomation flows |

Once feature count grows past roughly 40 files per feature, extract
`Domain` and `DesignSystem` into local Swift packages for compile-time
boundaries. Not needed yet.

---

## 4. Dependencies

| Dependency | Status | Reason |
|---|---|---|
| SwiftUI, Foundation | in use | UI and core types |
| SwiftData | Phase 1 | on-device persistence, offline-first store |
| HealthKit | Phase 7 | read weight/steps/workouts/sleep, write nutrition/water/workouts |
| UserNotifications | Phase 3 | optional reminders |
| StoreKit 2 | Phase 9 | VESS+ subscriptions |
| Vision / VisionKit | Phase 2 | barcode scanning (`DataScannerViewController`) |
| [supabase-swift](https://github.com/supabase/supabase-swift) | Phase 7+ | Auth, Postgres, Storage, Edge Functions. Only third-party dependency planned |

No third-party packages are installed today.

---

## 5. Domain models

All models are `Codable`, `Hashable`, `Sendable` structs with `UUID` ids.
Units are explicit in property names (`weightKilograms`, `volumeMilliliters`)
and stored in metric. Display conversion to imperial happens in presentation
through `Measurement` formatting.

| Model | Key decisions |
|---|---|
| `UserProfile` | Stores `dateOfBirth`, not age (computed via `age(on:calendar:)`). Enums for `Sex`, `WellnessGoal`, `ActivityLevel`, `DietaryPreference`, `Allergen`, `FocusArea`. Free text only for "custom"/"other". |
| `NutritionTargets` | Calories + three macros. Computed deterministically, user-editable. |
| `NutritionFacts` | Core four always present. Fiber/sugar/sodium optional (unknown ≠ 0). Extensible via `additional: [NutrientID: Double]`. Supports `scaled(by:)` and `+`. |
| `Food` | Nutrition per `servingSize` × `servingUnit`. `FoodSource` records where data came from (AI estimates always labeled). `FoodQuality` is descriptive (NOVA-aligned), never a verdict. |
| `FoodLogEntry` | **Snapshots** name and nutrition at log time: history survives food edits/deletes and works offline. `MealType` enum (custom slots later). |
| `Meal` | Reusable/planned group of food components with total nutrition. |
| `Drink` / `HydrationLog` | Drinks defined per 100 ml; `log(...)` produces a snapshot. `hydrationContributionPercent` (0–100) sets how much of the volume counts toward the water target. Defaults come from `DrinkPreset`/`DrinkType` (flat white 79%, so 240 ml counts as about 190 ml), and the user can change them per log or save their own default (`UserProfile.hydrationContributionOverrides`). The volume drunk and its nutrition are never changed by this; the UI always shows both figures. It's an adjustable estimate, not a measurement. |
| `Workout` / `Exercise` | Simple: schedule, complete, history. `templateID` links to templates (Phase 4). |
| `InventoryItem` | The "PantryItem" in the spec. `QuantityUnit` shared with food. `InventoryStatus` keeps consumed/discarded for food-waste insights. `reminderSnoozedUntil` supports snooze. |
| `ExpirationStatus` | Calendar-day based (`today`, `tomorrow`, `soon(days:)`, …), DST-safe, threshold 3 days. |
| `Supplement` / `SupplementLog` | User-entered dosage only. Schedule: daily / weekdays / as needed. |
| `WeightEntry`, `BodyMassIndex` | BMI is a value only; no classification or diagnosis. |
| `Insight` | `ruleID`, `severity`, `category`, `dataSource` (rule / aiAssisted / appleHealth), `expiresAt`. |

---

## 6. Data flow

```
View ──intent──▶ ScreenModel (@Observable, @MainActor)
                    │  async calls
                    ▼
               Repository (protocol)
                    │
          ┌─────────┴──────────┐
     SwiftData store      SyncEngine ──▶ Supabase
     (source of truth)    (outbox, background)
```

1. A view sends intent (for example "log 250 ml water") to its screen model.
2. The screen model calls a repository, which writes to SwiftData immediately
   and appends a change record to a local **outbox**.
3. The UI updates from local data; no spinner, no network.
4. The `SyncEngine` drains the outbox when online (`NWPathMonitor`), pushes
   changes and pulls remote changes since the last cursor.
5. Conflicts resolve per record by `updatedAt` (last writer wins). Log entries
   are append-only, so conflicts are rare by design.

**As built in Phase 1:** one concrete `LocalStore` (`Data/Local/`), an
`@Observable` main-actor class injected with `.environment(store)`.

- SwiftData records (`StoredProfile`, `StoredFoodLogEntry`,
  `StoredHydrationLog`) keep the query columns (`id`, `loggedAt`) plus the
  full domain value as Codable JSON. Domain types stay persistence-free, and
  new optional fields need no migration.
- Previews and UI tests use the same class on an **in-memory** container,
  so no repository protocols were needed yet. Protocols get introduced if a
  second real implementation appears (for example a sync-aware store).
- Screens derive everything through pure domain rules: `DaySummary` (Day
  Word, pace, macros, hydration), `NutritionTargetCalculator`, meal suggestions.
- Workouts, inventory and insights are not persisted yet (Phases 4–6). In
  production they are empty, so their Today sections stay hidden.

**Sample data** (`MockData`) is compiled only into Debug builds. It's used by
previews, unit tests, and the `-seedSampleData` launch argument, always in
memory and never written to the real store.

---

## 7. Service boundaries

| Service | Responsibility | Phase |
|---|---|---|
| `HealthService` | Authorization per data type, reads, writes | 7 |
| `NotificationService` | Authorization, schedule/cancel reminders by category | 3 |
| `AIService` | Food recognition, meal generation, insight phrasing | 8 |
| `SubscriptionService` | Products, purchase, restore, entitlement stream | 9 |
| `AnalyticsService` | Product events from a closed enum; no PII | 1 (no-op), later real |

All services are protocols with a live and a preview implementation, injected
through the environment. Views never import HealthKit/StoreKit directly.

**Error handling:** services throw typed domain errors. Screen models map
them to a user-facing state ("Something went wrong." + Retry). Technical
details go to `os.Logger` with private interpolation for user data.

---

## 8. HealthKit strategy (Phase 7)

- **Contextual permission, never during onboarding.** Onboarding step 8 only
  *explains* Apple Health and offers "Connect Apple Health" or "Not now".
  Each feature requests only its own types when first used (for example
  Activity requests workouts and active energy).
- **Read:** body mass, height, steps, active energy, workouts, sleep analysis,
  heart rate (only if an insight needs it).
- **Write:** dietary energy and macros, dietary water, workouts, body mass.
  Writes are opt-in per category.
- Imported samples are stored with `MeasurementSource.appleHealth` so VESS
  never writes back data it read (no duplicate loops).
- Health data never leaves the device unless the user enables cloud sync,
  and is never used for advertising.

---

## 9. Supabase strategy (Phase 7+)

- **Auth:** Sign in with Apple (primary) and email magic link. Session tokens
  stored in the Keychain. Only the **anon key** ships in the app; the
  service-role key exists only in Edge Functions.
- **Tables:** `profiles`, `foods`, `food_logs`, `meals`, `drinks`,
  `hydration_logs`, `workouts`, `exercises`, `inventory_items`, `supplements`,
  `supplement_logs`, `weight_entries`, `insights`, `subscriptions`.
  Columns mirror domain models in snake_case; enums as `text` with `CHECK`.
- **Row Level Security on every table**, for example:
  ```sql
  alter table food_logs enable row level security;
  create policy "own rows" on food_logs
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  ```
  Shared reference data (a public food database) is read-only to clients.
- **Sync:** every row has `updated_at` (trigger-maintained) and `deleted_at`
  (soft delete) to support incremental pull.
- **Deletion:** an Edge Function deletes the auth user and cascades all rows
  and storage objects. Exposed in Profile → Privacy.

---

## 10. AI strategy (Phase 8)

- **No AI keys in the app.** The client calls a Supabase Edge Function, which
  holds provider keys, enforces auth, rate limits and VESS+ entitlement, and
  calls the provider (OpenAI, Gemini, …). Providers are swappable server-side.
- Client protocol (planned):
  ```swift
  protocol AIService: Sendable {
      func recognizeFood(in image: Data) async throws -> [FoodEstimate]
      func generateMeals(_ request: MealGenerationRequest) async throws -> [MealSuggestion]
      func phrase(_ insights: [Insight]) async throws -> [Insight]
  }
  ```
- **Estimates are labeled.** Recognized foods are saved with
  `FoodSource.aiEstimate` and shown as estimates the user confirms or edits.
- **AI never computes truth.** Meal generation receives targets computed on
  device; returned meals are re-totaled locally from `Food` data.
- **On-device option.** Evaluate Apple's FoundationModels framework for
  insight phrasing on supported devices before sending anything to the cloud.
- Clear consent screen before the first AI use explaining what is sent.

---

## 11. Subscription strategy (Phase 9)

- StoreKit 2 only: `Product.products(for:)`, `purchase()`,
  `Transaction.currentEntitlements`, `Transaction.updates`.
- `SubscriptionService` exposes `entitlement: Entitlement` (`.free` / `.plus`)
  as an async stream; features gate on `Entitlement`, never on product IDs.
- The server validates entitlement (App Store Server API / notifications into
  `subscriptions`) for server-side features such as AI calls.
- A StoreKit configuration file covers local testing. There is no fake
  "unlock" flag in code.

| Free | VESS+ |
|---|---|
| Food logging, macros, water, weight, BMI, basic workouts, grocery list, basic expiration | AI food recognition, AI meal planning, advanced/energy insights, food quality analysis, advanced analytics, smart grocery planning, advanced Apple Health insights |

---

## 12. Insights engine (Phase 6)

```swift
protocol InsightRule: Sendable {
    var id: String { get }   // e.g. "nutrition.protein_target_streak"
    func evaluate(_ context: InsightContext) -> Insight?
}
```

`InsightContext` is a read-only snapshot of recent logs and targets. Rules are
pure, individually unit-tested, and ranked by severity and recency. Copy uses
correlation language ("On days when…", "You tend to…") and never claims
causation. The Today screen shows at most one or two.

---

## 13. Design system

- **Color:** semantic tokens in `Assets.xcassets/Colors`, each with a light and
  dark variant, accessed via `VESSColor`. Warm stone canvas, ink primary, a
  single muted cobalt accent, restrained sage/amber/brick for state. All text
  pairs meet WCAG AA.
- **Type:** `VESSTextStyle` on top of Dynamic Type. New York serif for
  display/large title (editorial voice); San Francisco everywhere else;
  monospaced digits for metrics; `metricLarge` scaled with `@ScaledMetric`.
- **Layout:** spacing scale 4–48, three radii (8/14/22, continuous corners),
  44 pt minimum hit target, 52 pt controls, one very soft light-mode elevation.
- **Liquid Glass:** system bars (tab bar, navigation, toolbars) use it
  automatically. Content uses solid surfaces; no glass in the content layer.
- **Components:** `VESSButtonStyle` (primary/secondary/tertiary),
  `VESSCard`, `VESSTextField`, `VESSChip`, `VESSProgressBar`, `VESSScreen`,
  `VESSSectionHeader`. State is never conveyed by color alone.

---

## 14. Testing

- **Unit (Swift Testing, `VESSTests`):** nutrition scaling and totals,
  optional-nutrient semantics, hydration progress, drink scaling, expiration
  (day offsets, time-of-day, DST), BMI, age. Tests pin a fixed calendar and date.
- **Planned:** target calculator, insight rules, repository round-trips
  (in-memory SwiftData), sync conflict resolution; XCUIAutomation flows for
  onboarding, food/water logging, workout completion, navigation, paywall.
