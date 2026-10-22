# Add a drink: current screen vs reference 10 (and G01/G02)

Reference `10-hydration-sheet` is the "Add a drink" sheet. `G01`/`G02` are a
separate "Custom amount" screen. Before this change the sheet was built from
G01 alone (captures: `before-1.png`, `before-3.png`).

| # | Reference 10 | Current sheet (before) |
|---|---|---|
| 1 | Header: HYDRATION caps label, big "1.6" with "of 2.2 L", close button | "Add a drink" title, editorial line "A little more water.", "Hydration · 1,6 of 2,2 L today" (G01's header) |
| 2 | Thin water progress bar under the header | None |
| 3 | Four category chips: Water, Tea, Coffee, Other | Eight drink chips in three wrapping rows (Water, Sparkling water, Black coffee, Flat white, Tea, Juice, Soft drink, Other drink) |
| 4 | Four size cards with an outline glass icon: Glass 150, Mug 250, Can 330, Bottle 500 ml; selected card tinted (tintWater + strokeWater) | None. An amount stepper "− 250 ml +" with a typed field instead (G01's) |
| 5 | TODAY dot timeline 06–24, dot size by volume, "now" line | None |
| 6 | Today's drinks: time, icon in the water hue, name, amount, "· counts 270" when partial | None in the sheet (only in Nutrition › Drinks) |
| 7 | Footnote "Coffee counts at 80%, tea at 90%." | "Water counts at 100 %. An estimate you can change." with a native Stepper for the share (not in any reference) |
| 8 | Primary button "Add 250 ml water" | "Add 250 ml" |
| 9 | No time control | Native time picker row (G01 has a "Time · Now · 18:40 ›" row instead) |
| 10 | — | "Counts as 250 ml toward water." box (G01's), "Use this for … from now on" switch and a typical-values line (in no reference) |

## How the rebuild resolves them

- The sheet follows 10 exactly: header, progress bar, category chips, size
  cards, TODAY timeline, today's list, footnote, "Add 250 ml water".
- A small fifth **Custom** card opens the G01 screen (stepper, drink, "Counts
  as …", time row, G02 range error). The hydration-share adjustment and the
  "Use this from now on" switch move there, so no existing behaviour is lost.
- A compact **Time** row under the cards ("Now · 18:40 ›") opens a time
  picker. Not in reference 10; allowed in the brief.
- Deviation kept on purpose: when a category holds more than one drink (for
  example Coffee: drip, flat white…), a second, smaller chip row picks the
  drink. Reference 10 has only four drinks, so it doesn't need one.
- Deviation kept on purpose: the footnote states the selected drink's share
  ("Flat white counts at 79 %.") because the reference's "Coffee counts at
  80%" is not true for every coffee in the catalog (drip is 90 %).
