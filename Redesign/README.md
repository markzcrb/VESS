# VESS design handoff

This pack lets Claude Code re-skin the VESS iOS app to the dark-first WHOOP/Oura-style redesign.

**How to use:** place this folder at the repo root as `Redesign/` and move `CLAUDE.md` to the repo root, then tell Claude Code:

> Read CLAUDE.md and follow its workflow. Start with step 1 (inventory) and show me the table before changing code.

Contents:
- `CLAUDE.md`: the rules and workflow for Claude Code.
- `Design/`: 79 screen PNGs and the component sheets.
- `VessDesignSystem/`: Swift tokens and components.
- `docs/`: screen map, icons, motion, demo data and open product questions.

The Swift files were written to spec but have not been compiled yet. Claude Code should fix any build errors in step 2.

Figma source: https://www.figma.com/design/6V1ynZXb5VWWowRvUqMJ7j
