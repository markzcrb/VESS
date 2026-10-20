# VESS: instructions for Claude Code

This repo is the VESS iOS app (SwiftUI, SwiftData, iOS 26+). Read `VESS_ARCHITECTURE.md` for technical rules: they still apply in full.

## Current task: the dark-first redesign

Mark has approved a new visual design in the language of WHOOP and Oura. Everything for it is in `Redesign/`:

| Path | What it is |
|---|---|
| `Redesign/Design/screens/` | 79 reference PNGs, @2x (804 px = 402 pt, iPhone 17 Pro width). **Source of truth for layout.** |
| `Redesign/Design/components/` | Component variant sheets and the token sheet (`Tokens.png`). |
| `Redesign/VessDesignSystem/` | **Reference** Swift for the new tokens and components. It is NOT part of the app target (it sits outside `VESS/`, which is a file-system-synchronized group). It has never been compiled. |
| `Redesign/docs/SCREENS.md` | Every screen: file, flow, navigation, components. |
| `Redesign/docs/ICONS.md` | Figma icon → SF Symbol. |
| `Redesign/docs/MOTION.md` | Animation and haptics spec. |
| `Redesign/docs/DATA.md` | Canonical demo data and **mandatory overrides** (pescatarian + nut-free). |
| `Redesign/docs/PRODUCT-LOGIC.md` | Behaviour the design does not define. Ask before inventing it. |

### Precedence (important)

1. **Visuals:** `Redesign/` supersedes `VESS_DESIGN_SPEC.md` for colour, type, layout, tab bar and components. Do not delete the old spec. Once Mark approves, add a note at its top: "Visual sections superseded by Redesign/".
2. **Copy tone and honesty rules** from `VESS_DESIGN_SPEC.md` still apply: calm, never judgmental, "25 kcal above your target" (never red), patterns not causes, estimates always labelled.
3. **Architecture** (`VESS_ARCHITECTURE.md`) still applies in full: local-first, deterministic domain rules, views only render state, MainActor default, no third-party packages.
4. **Conflicts to raise with Mark before building** (do not decide alone):
   - **Fuel score (0–100).** The old spec rejected numeric scores as "looks like a medical measurement". The redesign makes Fuel the hero number. Fallback if Mark declines: the same ring showing qualitative state ("On track" / "Building" / "Full day") with the percent of energy target.
   - **Tab bar.** The redesign shows a floating capsule plus a separate + button. First try the native iOS 26 `TabView` (Liquid Glass) styled to match. Only build the custom `VessTabBar` if native can't get close.
   - **Food photography** on Plan and Recipe. The old spec said: the user's own photo, otherwise a quiet tile with a symbol. Keep that rule unless Mark supplies recipe photos.

## How to migrate (do not drop the reference files in as they are)

The app already has `VESS/Core/DesignSystem/` (`VESSColor`, `VESSTypography`, `VESSLayout`, `VESSButtonStyle`, `VESSChip`, `VESSRow`, `VESSMetric`, `VESSDayStrip`, `VESSNavigation`, `VESSCard`, `DesignSystemGallery`, …) and `Assets.xcassets/Colors`.

- **Tokens:** update the existing token types and asset-catalog colours to the values in `Redesign/VessDesignSystem/Theme/*.swift`. Keep the existing type names (`VESSColor`, …) and add the new tokens (metric hues, atmosphere, tints, scrims) to them. Remove the sage accent from UI chrome. Data hues stay data-only.
- **Components:**
  - Where a counterpart exists, restyle the existing component to match the reference (`VESSButtonStyle` → capsule primary/secondary/quiet; `VESSChip` → Chip; `VESSRow` → ListRow / MetricRow; `VESSMetric` → MetricStripItem / ScoreRing; `VESSDayStrip` → Plan week pills; `VESSNavigation` → centred tracked-caps title).
  - Add the new ones (`ScoreRing`, `StatusRow`, `InsightCard`, `MacroBar`, `ImpactRow`, `LegendChip`, `VessTag`, `VessSegmented`) under `VESS/Core/DesignSystem/Components/`, using the `VESS` prefix to match the codebase.
- Merge `Redesign/VessDesignSystem/Components/RedesignGallery.swift` into the existing `DesignSystemGallery`.
- **Typography:** editorial lines use the system serif (New York), at most one per screen. SF Pro everywhere else, with monospaced digits for numbers. Never bundle Newsreader; it was a Figma stand-in.
- **Icons:** SF Symbols only (`Redesign/docs/ICONS.md`).

## Ground rules

1. **Tokens only.** No hex values, font sizes or spacing literals in feature views.
2. **Colour is data.** Metric hues only on rings, bars, deltas and metric icons. Everything else is greyscale. Links and CTAs use the link accent.
3. **Lists.** Use hairline lists, not stacked cards. Allowed card types: InsightCard, ImpactRow, embedded Coach card, featured recipe, sheets.
4. **No emoji, sparkles, gradient text or glassmorphism** (the tab bar material is the only exception).
5. **Dark-first.** Keep the Appearance setting (System / Light / Dark). Every token has a Light value.
6. **Accessibility.**
   - Dynamic Type up to AX5 (compare with `J0*.png`).
   - Targets are at least 44 pt.
   - VoiceOver labels on rings and rows.
   - Large Content Viewer on the tab bar.
   - Respect Reduce Motion.
7. **Don't change business logic while re-skinning.** Reuse the existing domain rules: `NutritionTargetCalculator`, `DaySummary`, `HydrationLog` contribution %, `ExpirationStatus` (3-day threshold), `OpenFoodFactsClient`, `FoodSearch`. Missing behaviour is stubbed with `Redesign/docs/DATA.md` values in `MockData` and listed in your summary.
8. Keep the unit tests green (`VESSTests`).

## Workflow

1. **Inventory.**
   - Table: every screen in `Redesign/docs/SCREENS.md` → the existing view file (`Features/…`), or NEW.
   - Table: every reference component → the existing `VESS*` component, or NEW.
   - List the conflicts from the Precedence section.
   - **Stop and show Mark.**
2. **Foundation.**
   - Update the tokens and Assets colours; restyle and add components.
   - Build.
   - Check `DesignSystemGallery` previews in Dark, Light and AX5 against `Redesign/Design/components/*.png`.
3. **Shell.** Tabs are Today · Nutrition · Plan · You, plus the + action (Add sheet: search, saved meals, photo, barcode, manual). Check `RootTabView` first: the redesign has 4 tabs + an add action.
4. **Screens, one at a time,** core first, in the order of `SCREENS.md`. For each screen:
   - build it;
   - run it on the iPhone 17 Pro simulator in Dark;
   - capture with `xcrun simctl io booted screenshot /tmp/<name>.png`;
   - compare with `Redesign/Design/screens/<name>.png`; the simulator is @3x, the reference is @2x, so scale the reference by 1.5;
   - fix differences greater than about 2 pt.
   - Check Light mode where an `L0*` reference exists.
5. **States:** empty, loading and error variants.
6. **Motion:** apply `MOTION.md`.
7. After each flow, give a short summary: files changed, screens done, stubs, open questions. Commit per flow on a `redesign` branch.

## Design facts that are easy to get wrong

- Width 402 pt, 20 pt side margins, section gap 32–36 pt. Detail screens have a centred TRACKED CAPS nav title and no tab bar.
- **Ring stroke is about 9.5 % of the radius** (11.8 pt on the 248 pt hero ring), flat caps, starting at 12 o'clock. `Tokens.png` says "of diameter"; that is a typo.
- The Fuel ring is neutral white; other rings use their metric hue.
- MacroBar: grey = already logged today; hue = what this item adds.
- ImpactRow: centre-zero bar; HURTS extends left in amber, HELPS extends right in green; scale ±26 %.
- Sheets: 32 pt top radius, elevated background, 36×5 grabber, background dimmed by 60 %.
- **The reference PNGs contain chicken and almond items.** Mark is pescatarian and nut-free, so replace them per `docs/DATA.md`. The layout stays the same.
