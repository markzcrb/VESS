> **Visual sections superseded by Redesign/**

# VESS — Design Specification

Status: **Draft for approval** (written after Phase 0, before Phase 1)
Sources: the reference set in `~/Desktop/VESS/`. Colors below were sampled
from the image pixels, then adjusted only where needed to pass contrast.

---

## 0. Reference map and source priority

| # | Area | VESS references (primary) | Other references (inspiration only) |
|---|---|---|---|
| 1 | Brand identity and logo | `ChatGPT … 12_05_26` (brand board: wordmark, V leaf mark, 4 app icon variants, palette) · welcome and splash panels in `ChatGPT … 12_03_26` | — |
| 2 | Today | `VESS Screens-selection2` (light, high fidelity) · `-selection4` (dark, "Full day" state) · `-selection` 1a | `12_03` Today panel (older concept) |
| 3 | Nutrition and logging | `-selection3` (day diary) · `-selection` 1b Nutrition, 1c Add food sheet, 1d Food detail | `12_03` Nutrition and "Track your drinks" panels |
| 4 | AI food recognition | `-selection5` camera → `-selection6` recognizing → `-selection7` result → `-selection8` review | `12_03` "Scan your food" |
| 5 | Meal planning and recipes | `12_03` Plan panel (structure only) | — |
| 6 | Activity and workouts | `12_03` Activity panel (structure only) · Today activity card | — |
| 7 | Inventory and expiration | Today "Expiring soon" (`-selection2/4`) | `12_03` "Manage your groceries" |
| 8 | Insights and analytics | Today insight card (`-selection2/4`) | `12_03` "AI insights" · Vitala analytics (`a98e6d…`, `c09065…`, `8c488a…`) |
| 9 | Design system | Implied by the high-fidelity VESS screens | Vitala "UI Building Blocks" (`a9d30f…`) |
| 10 | Apple Health | `12_03` "Integration with Apple Health" + Profile "Integrations" row | — |

**Priority when references conflict:**
1. High-fidelity VESS screens (`VESS Screens-selection*`)
2. VESS brand board
3. VESS concept board (`12_03`). Use it for structure only; its colors and decoration are superseded.
4. Vitala (a different brand). Use only its general principles: whitespace, large light numerals, quiet charts.

### Decisions where references disagree

| Conflict | Decision | Why |
|---|---|---|
| Energy score "High 8.4/10" (`12_03`) vs. qualitative headline "On track" / "Full day" (high fidelity) | **Qualitative headline + one plain sentence** | A numeric score looks like a medical measurement; the spec forbids that |
| Green ring, bright green toggles, pastel multicolor tiles (`12_03`) | **Rejected.** Sage accent; monochrome tiles | The brand avoids excessive green and decoration |
| Red "expires in 2 days" text (`12_03`) vs. tinted pills (high fidelity) | **Tinted pills** | Subtle urgency |
| Stock food photos (`12_03`) vs. thumbnails (high fidelity) | **The user's own photo if one exists, otherwise a quiet fill tile with a symbol** | No stock imagery that misrepresents what was eaten |
| Black floating pill tab bar (Vitala) | **Rejected.** Native `TabView` (Liquid Glass on iOS 27) | Native navigation |
| Gauges, liquid blobs, saturated orange/blue/purple, "AI health score 92%", AI orb (Vitala) | **Rejected** | Off-brand, gamified, implies diagnosis |
| Nutrition sub-tabs Log / Meals / Ingredients / Grocery (`12_03`) | **Rejected.** Nutrition is the day diary; groceries live in Plan | Matches the high-fidelity Nutrition screen and the Plan tab's badge dot |
| Phase 0 tokens: cobalt accent, New York serif display, ink primary button, ink selected chip | **Replace** with sage accent, SF only, sage buttons, sage-tint chips | Every VESS screen uses these |

---

## 1. Brand

- **Name:** VESS. **Tagline:** "Your body. Better understood."
- **Mark:** two leaves forming a V (a vessel). Used for the app icon, the welcome screen and empty states. Not repeated in navigation.
- **Wordmark:** thin, widely tracked capitals. **Always used as a supplied vector asset**, never recreated with a system font.
- **App icon variants** match the iOS icon appearances:

| Appearance | Background | Leaves |
|---|---|---|
| Default | Ivory | Forest |
| Dark | Forest | Ivory |
| Tinted | Sage gradient | Ivory |
| Alternate | Charcoal | Ivory |

- **Brand palette** (marketing, icon, welcome):

| Name | Hex |
|---|---|
| Ivory | `#EAE7E0` |
| Stone | `#D4CEC3` |
| Sage | `#748176` |
| Forest | `#2F3830` |
| Charcoal | `#131313` |

- Brand Sage `#748176` has only 4.1:1 contrast on white, which fails for text. The UI therefore uses a darker sage, `#5F735C`, which matches the high-fidelity screens.
- **Voice:** calm, factual, never judgmental.
  - Over target reads "25 kcal above your target", never "over budget" or red.
  - Patterns use "On days when… / You tend to…", never cause and effect.

---

## 2. Color tokens (light / dark)

### Surfaces and text
| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#F7F7F4` | `#111312` | Canvas |
| `card` | `#FFFFFF` | `#1F2220` | Cards, sheets (1.16:1 on the dark canvas) |
| `fill` | `#EFEFEA` | `#2E322F` | Inputs, icon buttons, quiet buttons, tracks, thumbnails |
| `divider` | `#E7E7E2` | `#343835` | Hairlines, inset row separators |
| `text` | `#171817` | `#EDEDE8` | Primary text, selected tab |
| `secondaryText` | `#6E716D` | `#A6AAA4` | Supporting text (4.6:1 light, 6.8:1 dark on card) |
| `tertiaryText` | `#747772` | `#7C807A` | Future dates, chevrons (4.2:1 light, 4.0:1 dark on card). `#A4A7A2` is decorative only |

### Accent
| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#5F735C` | `#9FB49A` | Primary button fill, links, focus, selected text |
| `onAccent` | `#FFFFFF` | `#0E0F0E` | Text on accent fill |
| `accentTint` | `#DCE6D8` | `#2A3428` | Selected chip, batch tray |
| `insightSurface` | `#EAEFE7` | `#1C221B` | Insight card background |

### Data colors
Graphical objects only (dots, bars). Values are always also shown as text.

| Token | Light | Dark |
|---|---|---|
| `calories` | `#C27C4E` | `#DE9A6F` |
| `protein` | `#7D6A9C` | `#A797C8` |
| `carbs` | `#A88A3A` † | `#D4B96F` |
| `fat` | `#6E8C8E` | `#95B1B3` |
| `water` | `#4C86AA` | `#7FB0D0` |
| `activity` | `#6F8F50` | `#9BBD7A` |

† Sampled as `#B39545`, darkened to reach 3:1 contrast against the card.

### Status
| Token | Light | Dark | Use |
|---|---|---|---|
| `warning` | `#B07A2A` | `#D9A75A` | Dots |
| `warningText` | `#8A5A14` | `#E2B46C` | Badge text (the sampled amber fails AA as text) |
| `warningTint` | `#F5EBDA` | `#2E2618` | Badge background |
| `critical` / `criticalText` / `criticalTint` | `#B13A34` / `#9E2F2A` / `#F6E3E0` | `#F08A80` / `#F2A098` / `#33201E` | "Today" / expired only |
| `success` | = `activity` | = `activity` | Target reached |

Removed from Phase 0: `primary` / `onPrimary` (ink). Ink is now just `text`.

**Always dark (camera):** the AI camera flow uses fixed dark surfaces
(`#0B0C0B` canvas, `#212321` card) and `accent-dark` buttons in both
appearances.

---

## 3. Typography

San Francisco only. Every style scales with Dynamic Type, and all numbers
use monospaced digits. The serif display style from Phase 0 is removed.

| Style | Base | Weight | Example |
|---|---|---|---|
| `heroTitle` | 40 pt, `@ScaledMetric` | regular, −0.5 tracking | Today's Day Word: "On track", "Full day" |
| `dayWord` | largeTitle (34) | regular | Onboarding questions |
| `screenTitle` | system navigation large title | bold | "Nutrition" |
| `detailTitle` | title2 | semibold | "Salmon fillet, baked", "Looks like" |
| `sectionTitle` | headline | semibold | "Meals", "Expiring soon" |
| `rowTitle` | body | semibold | "Breakfast" |
| `body` | body | regular | Food row names, insight text |
| `secondary` | subheadline | regular | "Greek yogurt, berries…", "of 2,400 kcal" |
| `label` | footnote | regular | Card labels with dot ("Calories"), date line, group headers |
| `badge` | caption | semibold | "Tomorrow", "Approx." |
| `metricHero` | 64 pt, `@ScaledMetric` | light | Today's calories: "1,840" |
| `metricLarge` | 40 pt, `@ScaledMetric` | light | Nutrition's calories |
| `metric` | title (28) | regular | "1.4 L", "6,420" |
| `metricInline` | callout | regular | "108 / 140 g" (value in `text`, "/ 140 g" in `secondaryText`) |

- **Units** sit inline after a metric in `secondary` style, aligned to the first text baseline ("1.4 L", "312 kcal").
- **Truncation:** row subtitles use one line with a tail ellipsis. Headlines and insight text never truncate.

---

## 4. Layout

| Token | Value |
|---|---|
| Screen inset | 20 |
| Card padding | 20 |
| Gap between sections | 40 (up from Phase 0's 32, measured from the mockups) |
| Section header to content | 12 |
| Grid gap (Water / Activity) | 12 |
| Row height (thumbnail rows) | 76–82 · thumbnail 56, radius 12 |
| Row height (text rows) | ≥ 56 |
| Radius | small 8 · thumbnail 12 · control 16 · card 22 |
| Buttons | 52 high, radius 16 (continuous) · inline quick buttons are capsules |
| Hit target | ≥ 44 everywhere |
| Elevation | Light mode: hairline border + 4% shadow. Dark mode: tone only |

---

## 5. Components

| Component | Spec | Seen in |
|---|---|---|
| `VESSButtonStyle.primary` | Accent fill, `onAccent` semibold, 52 pt, radius 16, full width | "Continue", "Add to Dinner" |
| `.secondary` | `fill` background, `text` color | "Connect Apple Health" |
| `.tertiary` | Accent text, optional leading symbol | "+ Add to breakfast", "✦ Make something", "Cancel" |
| `.quick` | `fill` capsule, compact | "+250 ml" |
| `VESSIconButton` | 44–52 pt `fill` square (radius 16) or circle | Barcode, camera, "+" add, "×" close |
| `VESSCard` | As in Phase 0 | All cards |
| `VESSRowGroup` | Card of rows with inset dividers | Meals, foods, drinks, expiring |
| `VESSRow` | Optional thumbnail · title / subtitle · trailing value / secondary · accessory (`+`, chevron, badge, confidence dots) | Throughout |
| `VESSMetric` | `metricHero` / `metric` + unit + "of X" + optional trailing note ("560 left") | Calories, water, steps, food detail |
| `VESSProgressBar` | 4–6 pt capsule, data color on `fill` track. Over target: bar full, with a tick at the target | Calories, macros |
| `VESSSegmentedProgress` | Dashes (one per 250 ml of target) | Water |
| `VESSMacroSummary` | 3 columns: dot + label, inline metric, bar | Today, Nutrition |
| `VESSStatusBadge` | Tinted capsule + text: Today (critical), Tomorrow (warning), "In N days" (neutral `fill`) | Expiring |
| `VESSInsightCard` | `insightSurface`, 3 pt leading accent rule, "✦ Insight" label, "…" menu, body, secondary detail, link | Today |
| `VESSDayStrip` | Weekday letters + dates; selected day ringed in `text`; dot = has logs | Nutrition, Plan |
| `VESSChip` | Capsule; selected = `accentTint` background + `accent` text + checkmark | Serving presets, AI "Not sure?" options, filters, onboarding multi-select |
| `VESSOptionRow` | Full-width card row, title + optional detail, check when selected | Onboarding single choice |
| `VESSTextField` / `VESSQuantityField` | `fill` field, radius 16; quantity + unit menu side by side | Food detail serving, onboarding |
| `VESSSearchField` | `fill` capsule with magnifier; trailing icon buttons alongside | Add food |
| Segmented control | Native `Picker(.segmented)` | Recent / Favorites / Meals; Plan; Activity |
| `VESSBatchTray` | `accentTint` bar "1 item · 312 kcal … Done" | Add food |
| `VESSSheetHeader` | Title, secondary subtitle, circular × button | Add food, review estimate |
| `VESSConfidenceDots` | 3 dots, filled = confidence. Accessible label "High / Medium / Low confidence" | AI review |
| Bottom action bar | `safeAreaInset(.bottom)`: total line + primary button | Food detail, review |
| `VESSScreen` | As in Phase 0, with 40 pt section spacing | All tabs |

Charts (Phase 6+, Swift Charts):
- One series per chart, in its data color.
- A faint area fill at most.
- A dotted line for projections.
- At most 3–4 axis labels, plus a "Last updated" caption.
- No gauges and no donut rings.

---

## 6. Screens

### Today (high fidelity: `-selection2` / `-selection4`)
1. **Header:** date (`label`) on the left, circular "+" toolbar button on the right (quick add).
2. **Day state:** greeting (`secondary`), `headline` ("On track" / "Behind" / "Full day" / "Getting started"), and one sentence built from the data ("Protein is behind; water is behind."). The rules are deterministic and live in the domain layer.
3. **Calories card:** `VESSMetric` + bar + "N left" or "N above", then `VESSMacroSummary`. The chevron opens the Nutrition tab.
4. **Meals:** `VESSRowGroup` for Breakfast / Lunch / Snack / Dinner.
   - Logged meals: kcal and time, with "Approx." for estimates.
   - Missing meals: a `fill` "+" tile, "Add dinner / Usually around 19:30".
   - "Day diary" link to Nutrition.
5. **Water | Activity grid:**
   - Water: metric, segmented progress, inline "+250 ml" (logs immediately, haptic, Undo).
   - Activity: today's workout status. Steps appear only after Apple Health is connected (Phase 7). Steps are never mocked in shipping builds.
6. **Expiring soon:** up to 3 rows, each with location · quantity and a `VESSStatusBadge`, plus the item count. "✦ Make something" (AI, VESS+) is shown only once Phase 8 exists.
7. **Insight:** one `VESSInsightCard` and "See all insights".

### Nutrition (`-selection3`, 1b)
- Large title and "+" button.
- `VESSDayStrip`, then the calorie line and `VESSMacroSummary`.
- One section per meal: optional photo, `VESSRowGroup` of foods (estimates carry an "Approx." badge and "from photo"), "+ Add to …".
- Drinks section with caffeine total, "counts as N ml", and a neutral line such as "Your last caffeine was at 14:20."
- Footer links: Favorites · Custom foods · Recipes.

### Add food sheet (1c) → Food detail (1d)
- **Add food:**
  - Large-detent sheet titled "Add to [meal ▾]" (a menu).
  - Search field + barcode + camera buttons; segmented Recent / Favorites / Meals.
  - `VESSBatchTray` while adding several items.
  - Grouped suggestions ("Usually at dinner", "Earlier today and this week") with a verified seal, kcal and a "+" button.
- **Food detail:**
  - Photo, `detailTitle`, meta line (verified · source · estimated price when the budget focus is on).
  - Serving `VESSQuantityField` + preset chips.
  - `metricHero` kcal, then macro rows showing "33 g · 32 g left" with bars.
  - Sticky "Add to Dinner" button.

### AI food recognition (`-selection5` → `8`)
Always dark, full-screen cover.

1. **Camera:**
   - Circular × and flash buttons; a guidance pill ("Fit the whole plate in the frame"); a rounded frame.
   - Library thumbnail · shutter · search.
   - Privacy line: "Photo used only to estimate this meal".
2. **Recognizing:** thin progress line, "Matching foods / This usually takes a few seconds", "Cancel".
3. **Result:**
   - Labeled pins on the photo (uncertain items end in "?").
   - Card: "Looks like 3 items · approx. 585 kcal".
   - "Review estimate" button and "Retake".
4. **Review sheet:**
   - Rows with "approx." amounts and confidence dots.
   - "Not sure? Tap to choose" chips for uncertain items; "+ Add item".
   - Footer "Approx. 585 kcal · Estimated" and "Continue".
   - Logged entries keep an "Approx." label.

### Plan (`12_03`, restyled)
- Segmented Meals | Groceries | Recipes. The tab shows a badge while items are expiring.
- **Meals:** day strip, "Your plan for today" rows, "Generate plan" (VESS+, primary style), quick recipes.
- **Groceries:** "At home" inventory with filters (All / Expiring / location / category) and a shopping list. Row actions: consumed · discarded · snooze · edit date.

### Activity (`12_03`, restyled)
- Segmented Workouts | Steps | Stats.
- Today's workout (complete with checkmark), a monochrome "Start a workout" grid (SF Symbols on `fill`), "This week" list.
- Steps and Stats show a contextual "Connect Apple Health" prompt until connected.

### Profile (`12_03`, restyled)
- Monogram avatar (no photo required), name, "View and edit profile".
- Weight tile with sparkline and Height tile.
- Grouped rows: Goals · Body metrics (BMI is information only) · Supplements · Integrations › Apple Health · Notifications · Privacy & data · Help.

### Apple Health settings (`12_03`)
- Per-type rows (Steps, Workouts, Sleep, Weight, Heart rate) with icon, latest value, and a toggle tinted `accent`.
- The toggles are VESS preferences. The system permission sheet is requested only when a toggle is first turned on.

### Onboarding (no VESS mockup; derived from the system above)
- **Welcome:** the V mark + wordmark on Forest (dark) or Ivory (light), the tagline, a primary "Get started" button and a tertiary "I already have an account".
- **Steps 2–8:** one question per screen.
  - Thin step progress at the top and a back button.
  - Question in `headline`.
  - Options as `VESSOptionRow` (single choice) or `VESSChip` (multiple choice).
  - Sticky "Continue" button.
- **Apple Health step:** explains what is read and why. "Connect Apple Health" (secondary style) and "Not now" carry equal weight. No permission is requested here.

---

## 7. Interaction and motion
- One primary action per screen. Quick actions use sheets; detail screens push inside the sheet.
- Logging is optimistic and local: success haptic plus a 4-second Undo; no confirmation dialogs.
- Progress fills animate on first appearance with `.snappy`. With Reduce Motion they appear without animation.
- Haptics only on selection, log success and completion.
- AI results are always reviewed before logging; nothing AI-generated is logged without user confirmation.

## 8. Accessibility
- Every metric gets a spoken label, for example: "Calories, 1,840 of 2,400, 560 left".
- Bars and dots are hidden from VoiceOver when the value is already spoken.
- Badges and states always include text; confidence dots have spoken equivalents.
- At accessibility text sizes, two-column grids and macro rows stack vertically.
- The camera works with VoiceOver: the shutter is labeled, and recognition results are read out.
