# VESS screen map

All references are in `Design/screens/` at @2x, 402 pt wide. "Tab" = which tab bar item is active (— means a pushed detail with no tab bar).
Build order: **Core → Add/logging → Plan → Grocery/Pantry → Activity → Profile → States → Accessibility → Light**.

## Shell
- Tabs: **Today · Nutrition · Plan · You**. The **+** button (separate circle) opens the Add sheet (05) with entry points: search, saved meals, photo (I02), barcode (F01), manual (H01).
- The Coach icon (top-right on Today) opens 12.

## Core (dark)
| File | Screen | Tab | Reached from | Key components |
|---|---|---|---|---|
| 01-today | Today | Today | root | MetricStripItem ×5, ScoreRing (Fuel), editorial headline, MetricRow ×4 + LegendChip, InsightCard, intake bars (24 h), MealRow ×4, MacroBar (water), ListRow (tomorrow) |
| 02-energy | Energy detail | — | Today ring / Energy row | day picker, ScoreRing (energy), StatusRow ×4, InsightCard, cumulative line chart with meal icons + now line, 7-day bars with dashed target |
| 03-macros | Macros detail | — | Today strip / Nutrition | VessSegmented, 3 concentric rings, LegendChip, MacroBar ×3, stacked share bar, InsightCard, protein 7-day bars |
| 04-insights | Journal insights | — | InsightCard CTA | editorial title, HURTS / % IMPACT / HELPS header, ImpactRow ×8, footnote |
| 05-add-food | Add to dinner | — (sheet/push from +) | + | search field + barcode, Chips, saved meals ListRow, food rows with IconButton (+ / filled ✓), sticky add bar |
| 06-food-detail | Food | — | food row | big kcal, MacroBar ×3 (logged + adding), Chips (serving), stepper, ListRow meta, primary button |
| 07-plan-week | Plan · Week | Plan | tab | VessSegmented (Week/Recipes/Grocery), week day pills, editorial day title, ListRow slots, featured recipe card (photo), InsightCard |
| 08-recipe-detail | Recipe | — | featured recipe | full-bleed photo + fade, stats row, macro key, servings stepper, ingredient rows + VessTag, numbered method, sticky 2-button bar |
| 09-activity | Activity | — | Today Steps | ScoreRing (activity), MetricRow ×3, InsightCard, steps 7-day bars, workout rows + VessTag (Recorded/Entered), honesty footnote |
| 10-hydration-sheet | Hydration | sheet over Today | Today hydration "Add drink" | big litres, progress bar, drink-type Chips, 4 quick-add tiles (selected = tintWater + strokeWater), day timeline, log list, primary button |
| 11-profile | You | You | tab | avatar + name, weight card (editorial line, 78.4 kg, range band chart, "−0.6 kg in 12 weeks" pill), goals ListRows, preferences ListRows |
| 12-coach | Coach | — | Today chat icon | chat (user bubble bgRaised), embedded metric card, suggestion Chips, composer |

## States
| File | Screen |
|---|---|
| S1-today-first-log | Today, nothing logged (ring empty, values "—", "Log a meal") |
| S2-today-loading | Today skeleton ("Syncing with Apple Health…") |
| S3-insights-not-enough-data | Insights: 12/30 days ring, ghost rows at 28 % opacity, tagging list |
| S4-activity-no-health | Activity without Apple Health ("VESS doesn't guess your steps.") |

## A · Plan
A01 week (full) · A02 add meal to Thu dinner · A03 planned meal detail · A04 tonight → log from plan · A05 move meal (sheet) · A06 suggest loading · A07 suggest results · A08 suggest error · A09 next week empty · A10 last week logged.

## B · Grocery (Plan › Grocery)
B01 by aisle · B02 by meal · B03 checked → "Done shopping · store N items" (moves to Pantry) · B04 item · B05 add item (sheet) · B06 empty.
Rule: **checking an item is not storing it**. Only "Done shopping" transfers checked items to Pantry.

## C · Pantry
C01 overview ("use soon" first, grouped Fridge / Freezer / Cupboard / Counter) · C02 item (quantity, stored in, expiry, planned in) · C03 add (sheet) · C04 empty.

## D · Activity
D01 steps hour by hour · D02 workout detail (Recorded) · D03 add workout (type, duration, effort, when → "≈ 150 kcal · estimate") · D04 history · D05 statistics · D06 syncing · D07 sync error (keeps last known 6,420 steps / 412 kcal from 16:20, Retry).

## E · Profile destinations (grouped settings lists)
E01 goals · E02 body · E03 nutrition preferences (Pescatarian ✓, avoid Nuts ✓) · E04 supplements · E05 Apple Health (read/write toggles) · E06 notifications · E07 privacy · E08 VESS+ (€39.99/year) · E09 settings (appearance System/Light/Dark) · E10 help.

## F · Barcode
F01 scanner · F02 detected/reading · F03 product found (sheet) · F04 product detail (label values only) · F05 not found → Add manually · F06 camera denied → Open Settings / type number.

## G · Hydration additions
G01 custom amount · G02 validation (1–2,000 ml).

## H · Manual entry
H01 empty · H02 filled (with macro check note) · H03 validation.

## I · Nutrition diary and photo estimate
I01 Nutrition tab day diary · I02 camera · I03 recognizing · I04 review photo · I05 estimated items ("Three items. You decide.") · I06 adjust portion · I07 dinner estimate · I08 Nutrition with "Added to Dinner · Estimated" toast + Undo · I09 Today "Full day" (calm, no red when slightly over).

## J · Accessibility
J01 AX3 light (numbered VoiceOver order) · J02 AX3 dark · J03 AX5 light · J04 AX5 dark with tab bar Large Content Viewer. Content reflows vertically and nothing truncates.

## L · Light checks
L01 Today light · L06 Food detail light. Every other screen uses the same tokens; verify Light on at least the Today, Nutrition, Plan and Profile roots.

## K · Cycle and Habits (new, Figma section "New · Cycle and Habits")
| File | Screen | Tab | Reached from | Key components |
|---|---|---|---|---|
| 13-cycle | Cycle tracking: cycle-day ring, editorial estimate, month calendar, log today (all 7 symptom chips, as on 15), recent cycles | — | Today cycle row (only when "Cycle tracking" is on in You) | ScoreRing (metric/cycle), CalendarDay (Default/Muted/Logged/Estimated/Today), Chip, ListRow, Button Secondary |
| 15-cycle-log-sheet | Log or edit one day: date, flow, symptoms, note, Save / Delete this day | — | Tap a calendar day, "Period started today", Add sheet | Chip, ListRow, text field, Button Primary + Quiet |
| 14-habits | Habits: week of mini rings, "4/6" hero ring (neutral), today's list with 7-day dots, 4-week grid, pattern card | — | You › Habits, Today habits row | MetricStripItem, ScoreRing, HabitRow (Done Yes/No), InsightCard |
| 16-add-habit-sheet | Add a habit: auto-tracked suggestions, own name, how often, category, reminder | — | + in the Habits nav bar, "Add a habit" | ListRow, SegmentedControl, Chip, Button Primary |
| L13-cycle-light · L14-habits-light | Light versions of 13 and 14 | | | |

Notes: new tokens `metric/cycle`, `atmos/cycle`, `tint/cycle` (Dark + Light). Habit dot colour = the metric of its category (water, protein, activity, energy); others use text/primary. No streaks anywhere. Cycle copy always says estimates can be off, not medical advice, not contraception. No fertile window or ovulation.

## M · Plan calendar and Drinks sheet (new, Figma section "New · Plan calendar and Drinks")
| File | Screen | Tab | Reached from | Key components |
|---|---|---|---|---|
| 17-plan-week-calendar | Plan › Week with the week strip under the date title; day sections below | Plan | Plan tab | SegmentedControl, PlanDay (new), IconButton, Button Primary, ListRow, SectionHeader, TabBar |
| 18-plan-month-open | Same screen with the month grid open (tap the title or its chevron); a day in another week is selected, so the "Today" chip shows | Plan | Title chevron on 17 | PlanDay (Show weekday off), Chip, IconButton |
| 19-drinks-coffee | Drinks sheet, Coffee › Latte: category chips, drink tabs, size cards, time, caffeine, today timeline and list, pinned add button | — | Today hydration row, Add sheet | Chip, ListRow, Button Primary |
| 20-drinks-alcohol | Drinks sheet, Alcohol › Wine: size cards, time, strength (ABV), kcal note | — | Same sheet | Chip, ListRow, Button Primary |
| L17-plan-week-calendar-light · L19-drinks-coffee-light | Light versions of 17 and 19 | | | |

Notes:
- New component `PlanDay`: State Default / Selected / Today / Muted × Dot None / Some / All, text props Weekday and Day, boolean Show weekday. Neutral colours only, never a metric colour. Selected wins over Today; Today shows as a ring only when not selected. Dot: filled = all main meals planned or logged, hollow = some, none = nothing.
- 17 also fixes the day rows: "Nothing logged" / "Nothing planned yet" start at the same leading edge as the day header. Past days say "Nothing logged", today and future days say "Nothing planned yet".
- Week strip: 7 equal columns, tap a day to scroll the list to it; arrows and horizontal swipe change week. Month grid: always six rows so the height never jumps.
- Drinks sheet layout rule: nothing is wider than the sheet. Every row starts at the 20 pt margin. The category chips fit in one row at default text size (they scroll at larger sizes). The drink tabs row is a horizontal scroller that starts at the margin and bleeds off the right edge of the sheet only (the cut-off "Fl…" is the scroll hint, not a bug).
- Size cards: always 3 presets + Custom, equal widths, per drink (Latte 250/350/450, Wine 125/150/250, Water 250/330/500).
- The second row lists the drinks of the chosen category; it is hidden when a category has a single drink.
- Alcohol: kcal count toward energy, not toward Fuel and not toward water. Neutral copy, no advice.

## Not designed yet (ask Mark before building)
Plan › Recipes tab list · Add food search results / no results · edit a logged meal · weight entry + measurements · onboarding.
