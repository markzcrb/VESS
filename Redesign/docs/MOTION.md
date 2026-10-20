# Motion and haptics

Motion should feel calm and confident. When **Reduce Motion** is on, every animation below becomes an instant state change, or a crossfade of 0.2 s or less.

| Where | What | Spec |
|---|---|---|
| ScoreRing, MetricStripItem | Arc sweeps from 0 to its value on first appear | `easeOut(0.8)`, starts at 12 o'clock |
| Hero numbers | Count up with the ring | `.contentTransition(.numericText())` + the same 0.8 s animation |
| MetricRow / StatusRow lists | Rows fade and rise 6 pt, staggered | 40 ms per row, `easeOut(0.35)` |
| InsightCard | Border brightens once, about 0.9 s after appear | `easeInOut(0.6)`, then stays |
| Charts | Line draws left to right; bars grow from the baseline | `easeOut(0.6)`, bars staggered 20 ms |
| Logging (add food, add drink, add workout, Cook & log) | Light impact haptic, toast slides up with **Undo** for 5 s | `.sensoryFeedback(.impact(weight: .light))`; toast uses a spring (0.38, 0.86) |
| Sheets | Native detents, dimmed background | `.presentationDetents`, `.presentationCornerRadius(32)` |
| Segmented control / tab selection | Selected pill slides | `matchedGeometryEffect`, `snappy(0.25)` |
| Photo recognizing (I03) | Frame outline pulses slowly while estimating | opacity 0.4 → 1, 1.2 s, repeating; no spinner |
| Barcode detected (F02) | Frame snaps to the code; success haptic | `.sensoryFeedback(.success)` |
| Skeleton (S2, D06) | Shimmer sweep across skeleton blocks | 1.4 s linear, repeating; static under Reduce Motion |
