# Motion clips (simulator, iPhone 18 Pro, Dark, demo data)

Recorded with `xcrun simctl io booted recordVideo`. The simulator records
only when the screen changes and runs a Debug build, so judge timing and feel
on a device.

| Clip | What it shows | MOTION.md row |
|---|---|---|
| `01-today-ring-countup.mp4` | Launch to Today: Fuel ring sweep with the number rolling up from 0, strip rings, breakdown rows staggering in | ScoreRing, Hero numbers, MetricRow lists |
| `02-energy-rows-chart.mp4` | Energy detail: ring, status rows staggering, line drawing left to right, then the 7-day bars growing | StatusRow lists, Charts |
| `03-plan-segmented.mp4` | Plan: Week → Grocery → Recipes (DEBUG) → Week | Segmented control |
| `04-toast-undo-water.mp4` | Today: +250 ml, toast with Undo, Undo tapped | Logging |
| `05-toast-undo-food.mp4` | Add sheet → Apple → Add to dinner; "Added 1 item to Dinner" with Undo, Undo tapped | Logging, Sheets |
| `06-sheets.mp4` | Add sheet open and drag-dismiss, then the Fuel info sheet. Shows the first-open blank screen (about 1.6 s) listed under open issues | Sheets |
| `07-reduce-motion-today.mp4` | Launch and +250 ml with Reduce Motion switched on via `defaults write`; not confirmed the app picked it up | Reduce Motion |
