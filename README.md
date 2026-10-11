# VESS

> Your body. Better understood.

VESS (from *vessel*) is a native iOS wellness app that helps people understand
what they eat and drink, how they move, what they have at home and what's
about to expire, and how those habits relate to their day.

It brings together nutrition and macros, hydration, workouts, body metrics,
food inventory with expiration tracking, supplements and data-backed insights,
with optional Apple Health integration and AI assistance.

**Complexity underneath. Simplicity on top.**

---

## Architecture

SwiftUI app with a layered architecture: Features → Presentation → Domain →
Data/Services. It is local-first: all tracking works offline and syncs later.
All critical numbers (calories, macros, BMI, hydration, expiration) come from
deterministic, unit-tested Swift.

See **[VESS_ARCHITECTURE.md](VESS_ARCHITECTURE.md)** for layers, folder
structure, domain models, data flow, service boundaries and the HealthKit,
Supabase, AI and subscription strategies.

```
MyApp/
├── App/              entry point, tab shell
├── Core/DesignSystem tokens + components
├── Domain/Models     models and pure rules
├── Data/Mock         realistic mock dataset
└── Features/         Today · Nutrition · Plan · Activity · Profile
VESSTests/            Swift Testing unit tests
```

---

## How to run

Requirements: Xcode 27+, iOS 27 SDK.

1. Open `Untitled Project.xcodeproj`.
2. Select the **MyApp** scheme and an iPhone simulator.
3. **Run** (⌘R). A first launch shows onboarding; data is stored on device.
4. **Test** (⌘U) to run unit tests (`VESSTests`) and UI tests (`VESSUITests`).
5. Open `MyApp/Core/DesignSystem/DesignSystemGallery.swift` and use the
   canvas to see every component in light, dark and accessibility sizes.

**Debug launch arguments** (Scheme › Run › Arguments):

| Argument | Effect |
|---|---|
| `-uiTesting` | Starts with an empty in-memory store (onboarding every launch) |
| `-seedSampleData` | Starts with the clearly labeled sample day, in memory only |

Neither exists in Release builds, and neither touches your real on-device data.

There are no packages to resolve and no backend to start.

> The project still has Xcode's default names (`Untitled Project`, target
> `MyApp`), and lives in Xcode's temporary *UntitledProjects* folder. Move it
> to a permanent location and rename the project/target to `VESS` in Xcode.

**Temporary brand assets:** the wordmark is plain text and the app icon is a
text placeholder. Add an image set named `VESSWordmark` (vector) or
`WelcomeHero` (licensed image) to `Assets.xcassets` and the screens use them
automatically. Replace the PNGs in `AppIcon.appiconset` with the final icons.

---

## Development phases

| Phase | Scope | Status |
|---|---|---|
| 0 | Architecture, design system, structure, models, navigation, mock data | ✅ Done |
| 1 | Onboarding, Today, Nutrition day diary with quick add, drinks with hydration contribution, navigation | ✅ Done |
| 2 | Food catalog and search, Open Food Facts lookup, portions, meal assignment, editing entries, custom foods | ✅ Done (camera scanning and profile editing deferred) |
| 3 | Hydration, drinks, water reminders | |
| 4 | Activity, workouts, calendar, completion | |
| 5 | Food inventory, grocery list, expiration tracking | |
| 6 | Insights | |
| 7 | Apple Health | |
| 8 | AI | |
| 9 | StoreKit 2, VESS+ | |
| 10 | QA, performance, accessibility, App Store preparation | |

---

## Food data

- **Starter catalog** (`Data/Catalog/StarterCatalog.swift`): about 35 common
  foods with typical values per 100 g / 100 ml from USDA FoodData Central
  (public domain). Compiled into the app, so it works offline. IDs are
  derived from a stable key, so they never change between launches.
- **Your foods**: foods you create, products you open or log, and favorites
  are saved on the device (SwiftData). Logged entries keep a nutrition
  snapshot, so history never changes if a food is edited.
- **Open Food Facts** (`Data/Remote/`): online text search
  (Search-a-licious) and barcode lookup (`/api/v3/product/{barcode}`). Reads
  need no account or key. Data is community-contributed, shown as "not
  verified", and attributed in the app under the Open Database License
  (ODbL). Product images are not used. The client stays within the published
  limits (15 product reads and 10 searches per minute) and honors HTTP 429.
  Products are cached on the device and keep working offline.
- **Unknown is not zero**: a nutrient a source doesn't report is shown as
  "Not reported" and never counted as 0. A product without calories can't be
  logged.
- **Before release**: add a public contact (URL or email of the project, never
  a user's data) to the Open Food Facts User-Agent in
  `OpenFoodFactsClient.Configuration`.
- **Later**: USDA FoodData Central can be added as a second
  `RemoteFoodProvider` (needs a free API key, which must not be embedded in
  the app). Camera barcode scanning needs a camera permission text
  (`NSCameraUsageDescription`) and is not added yet; barcodes can be typed in.

UI tests run with `-uiTesting`, which replaces Open Food Facts with an
offline provider, so tests never touch the network.

---

## Environment variables

None are required today. From Phase 7 the app reads public configuration
from an `.xcconfig` that is **not committed** (`Config/Secrets.xcconfig`,
git-ignored) and surfaced through `Info.plist`:

| Key | Where | Notes |
|---|---|---|
| `SUPABASE_URL` | app | Project URL |
| `SUPABASE_ANON_KEY` | app | Public anon key, safe with RLS |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Functions only | **Never** in the app |
| `OPENAI_API_KEY` / `GEMINI_API_KEY` | Edge Functions only | **Never** in the app |

---

## Backend requirements (Phase 7+)

- A Supabase project with Auth (Sign in with Apple, email magic link).
- Postgres tables listed in the architecture doc, each with **Row Level
  Security** limiting access to `auth.uid() = user_id`.
- `updated_at` triggers and `deleted_at` soft deletes for incremental sync.
- Edge Functions: `ai-proxy` (auth + entitlement + rate limit + provider
  call), `delete-account` (cascade delete), App Store Server Notifications
  receiver.

## AI requirements (Phase 8)

- Provider keys live only in Supabase Edge Function secrets.
- The app calls `ai-proxy` with the user's session; the function verifies
  VESS+ entitlement and rate limits.
- AI outputs are labeled as estimates and re-validated on device; AI never
  produces the authoritative calorie or macro numbers.
- Users see what data is sent before first use.

---

## Privacy

VESS handles sensitive wellness data. It collects the minimum it needs,
stores it on device first, never uses health data for advertising, requests
Apple Health access per feature with a plain explanation, and supports full
account and data deletion.
