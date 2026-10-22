# Cycle (13, 15): notes for review

Sheets: `sheet-13-dark.png`, `sheet-13-light.png`, `sheet-15.png`, `sheet-AX5.png`, `sheet-SE.png`, `sheet-states.png` (empty, Today row on/off, You switch, Add sheet on/off). Images are git-ignored.

## Demo data (`-seedSampleData -demoClock -cycleOn`)
The demo clock is Tue 6 Oct, reference 13 is 22 Oct. The current period started 1 Oct (5 days), so today is cycle day 6. Six earlier cycles: 28, 30, 29, 31, 28, 29 days (average 29, range 28–31). Estimate: 29 Oct – 1 Nov, "in about 24 days". Today: no flow, Bloating. `-cycleOnEmpty` turns tracking on with nothing logged.

## Prediction thresholds (`CyclePrediction`)
| Rule | Value |
|---|---|
| Cycles used | last 6 completed |
| Needed for an estimate | 2 completed cycles (3 period starts) |
| Period day | flow Light, Medium or Heavy; Spotting never starts or extends a period |
| Gap inside one period | up to 2 days without flow |
| Cycles left out | shorter than 15 or longer than 60 days (usually a missed log) |
| Expected start | last start + rounded average |
| Window | last start + shortest … last start + longest; ±1 day when all equal |
| Less certain | longest − shortest > 7 days |
| After the window | "Your period may come later than estimated." |

## Deviations from the references
- The symptom chips on 13 show all seven (the PNG shows five), the same list as 15.
- Calendar always shows six weeks, so the height never jumps.
- The empty-state ring says "No estimate yet"; the editorial line carries "Log three period starts to see an estimate."
- At AX5 the legend stacks, and on the day sheet only Save is pinned (Delete moves to the end of the form).
- The (i) button is the system bar size (36 pt tall, like Back).
