# Text contrast (WCAG 2.1), worst surface per token

Computed from Assets.xcassets on 2026-10-21; translucent colours composited over the surface below. Surfaces: background, card, fill, surfaceGlass, sunken, every atmosphere, and each tag's own tint. Text needs 4.5:1; data graphics 3:1.

| Token | Worst surface (Light / Dark) | Light | Dark |
|---|---|---|---|
| text | atmosWater / atmosEnergy | 15.15 | 13.28 |
| secondaryText | atmosWater / atmosEnergy | 5.29 | 5.70 |
| tertiaryText | atmosWater / atmosEnergy | 4.54 | 4.54 |
| accent | tintLink / atmosEnergy | 4.75 | 6.78 |
| warningText | tintPoor / atmosEnergy | 4.52 | 7.35 |
| statusOptimalText | tintOptimal / tintOptimal | 4.72 | 8.28 |
| criticalText | atmosWater / atmosEnergy | 6.01 | 7.56 |
| onAccent | accentFill | 18.31 | 16.80 |
| calories (graphic, 3:1) | background | 3.47 | 9.11 |
| statusOptimal (graphic, 3:1) | background | 3.46 | 10.48 |
| statusPoor (graphic, 3:1) | background | 3.34 | 9.30 |
| activity (graphic, 3:1) | background | 3.97 | 9.85 |
| water (graphic, 3:1) | background | 4.59 | 7.70 |
| protein (graphic, 3:1) | background | 5.16 | 7.54 |

Changed in this pass: tertiaryText Light #696C68→#676A66, Dark #858985→#888C88; warningText Light #A35F12→#985911; warning tags and impact-row percents use the text tokens; search placeholders use tertiaryText.

Not text, so not held to 4.5:1: `decorative` (placeholder symbols, dashed chart rules, hidden from VoiceOver), `chartGuide` (grid lines), disabled controls.
