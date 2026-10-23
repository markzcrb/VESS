# Motion and haptics

Motion should feel calm and confident. When **Reduce Motion** is on, every animation below becomes an instant state change, or a crossfade of 0.2 s or less.

| Where | What | Spec |
|---|---|---|
| ScoreRing, MetricStripItem | Arc sweeps from 0 to its value on first appear | `easeOut(0.8)`, starts at 12 o'clock |
| Hero numbers | Count up with the ring | `.contentTransition(.numericText())` + the same 0.8 s animation |
| MetricRow / StatusRow lists | Rows fade and rise 6 pt, staggered | 40 ms per row, `easeOut(0.35)` |
| InsightCard | Border brightens once, about 0.9 s after appear | `easeInOut(0.6)`, then stays |
| Charts | Line draws left to right; bars grow from the baseline | `easeOut(0.6)`, bars staggered 20 ms |
| Logging (add food, add drink, add workout, Cook & log) | Success haptic, toast slides up with **Undo** for 5 s | `vessHaptic(.success)` (see Haptics); toast uses a spring (0.38, 0.86) |
| Sheets | Native detents, dimmed background | `.presentationDetents`, `.presentationCornerRadius(32)` |
| Segmented control / tab selection | Selected pill slides | `matchedGeometryEffect`, `snappy(0.25)` |
| Photo recognizing (I03) | Frame outline pulses slowly while estimating | opacity 0.4 → 1, 1.2 s, repeating; no spinner |
| Barcode detected (F02) | Frame snaps to the code; success haptic | `vessHaptic(.success)` |
| Skeleton (S2, D06) | Shimmer sweep across skeleton blocks | 1.4 s linear, repeating; static under Reduce Motion |

## Add sheet (21, 22)

| What | Spec | Reduce Motion |
|---|---|---|
| Carousel tiles | Every tile is 72 pt; the scale goes from 1 at the centre to 0.78 one slot (74 pt) away and beyond, and opacity from 1 to 0.85, continuously with the drag (`visualEffect` on the distance from the scroll view's centre) | No scaling animation: the centred tile is 1, the others 0.78 |
| Snapping | Whole 74 pt slots (a custom `ScrollTargetBehavior`, same feel as `.viewAligned`), with (width − slot) / 2 margins on both sides so the first and last tiles can centre. The landing tile is selected as the finger lifts, not when the deceleration ends (about 0.2 s after release); a fast flick keeps its momentum across several tiles. Taps and VoiceOver centre a tile with a one-shot `ScrollViewReader.scrollTo` (a bound `scrollPosition` re-applies itself on re-render and pulls against the finger) | Same; no scaling |
| Tap a tile | Scrolls it to the centre with `spring(response: 0.35, dampingFraction: 0.85)`; the selection follows when the scroll settles | Jumps there; selects at once |
| Type name under the carousel | Crossfades to the new name and colour, `easeInOut(0.2)` | Crossfade, 0.15 s |
| Content swap | When the landing tile is known: the old content slides 24 pt towards the side it leaves and fades out in `easeIn(0.14)`, the new content comes in 24 pt from the swipe side and fades in, `easeOut(0.28)`, so the two barely overlap. The swap happens inside a clipped full-height container, so the sheet doesn't jump | Crossfade only, `easeInOut(0.15)` |
| Haptic | Selection, once per settled change (not per tile passed) | Same |

Tokens: `VESSMotion.addTileScroll`, `addLabel`, `addSwap`, `addSwapReduced`, `addSwapOffset`.

## Haptics

All haptics go through `VESSHaptic` (`VESS/Core/DesignSystem/Tokens/VESSHaptics.swift`). There are four kinds and no others:

- **Add:** a soft impact.
- **Selection:** played by chips, tabs, segments, cards and calendar days.
- **Success:** played when something is saved or added.
- **Warning:** played when something is deleted.

A view plays a haptic on a state change with `vessHaptic(_:trigger:)`. An action whose view closes straight away (Save or Delete in a sheet) calls `haptics.play(_:)` on `\.vessHaptics`, and the app root plays it, so it isn't lost when the sheet closes. Haptics follow the system setting; VESS has no switch of its own.

| Where | Haptic | Trigger | Code |
|---|---|---|---|
| **+** (Add) in the tab bar | Add (soft impact) | Each tap | `RootTabView` |
| Tab bar | Selection | Tab changes | `RootTabView` |
| Chips, including cycle flow and symptoms | Selection | Chip selected or cleared | `VESSChip` |
| Segmented controls | Selection | Segment changes | `VESSSegmented` |
| Toggles | Selection | On or off | `VESSToggle` |
| Option rows | Selection | Option picked | `VESSOptionRow` |
| Cards: drink tiles and sizes, workout types, search filters | Selection | Card picked | `AddDrinkSheet`, `AddWorkoutView`, `FoodSearchSheet` |
| Drink amount and strength | Selection | Value steps | `AddDrinkSheet`, `EditDrinkSheet` |
| Favourite a food | Selection | Star toggled | `FoodDetailView` |
| Plan week strip and month grid | Selection | Selected day changes (tap, arrows, swipe, Today) | `PlanView` |
| Cycle calendar | Selection | Day opened to edit | `CycleView` |
| Food, drink, workout or Cook & log logged | Success | Each log (with the Undo toast) | `AppRootView` via `FoodLogUndo.loggedCount` |
| Water added on Today | Success | Each add | `TodayView` |
| Habit ticked | Success | Becomes done (unticking is silent) | `VESSHabitRow` |
| Habit saved or suggestion added | Success | Save | `AddHabitSheet` → `haptics.play` |
| Drink edited | Success | Save | `EditDrinkSheet` |
| Shopping stored in the pantry | Success | Done shopping | `GroceryViews` |
| Barcode recognised | Success | Code found | `BarcodeScannerView` |
| Food entry deleted (swipe or edit sheet) | Warning | Delete | `NutritionView`, `EditEntrySheet` |
| Drink deleted (swipe, Nutrition or drinks sheet) | Warning | Delete | `NutritionView`, `AddDrinkSheet` |
| Workout, habit, pantry item or supplement deleted | Warning | Delete | `ActivityDetailViews`, `AddHabitSheet`, `PantryItemView`, `SupplementsView` |
| Cycle data or all data deleted | Warning | Delete confirmed | `ProfileView`, `SettingsViews` |

