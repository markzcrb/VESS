# Habits (14, 16): notes for review

Sheets: `sheet-14-dark.png`, `sheet-14-light.png`, `sheet-16.png`, `sheet-AX5.png`, `sheet-SE.png`, `sheet-states.png`. Images are git-ignored.

Demo: `-seedSampleData -demoClock -habitsDemo` (demo day Tue 6 Oct, week Mon 5 – Sun 11; reference 14 is Thu 22 Oct).

## Rules (`HabitRules`)
| Rule | Value |
|---|---|
| Weekdays | Monday–Friday |
| Week | the locale's week (`Calendar.firstWeekday`) |
| N times a week | on today's list every day; complete when done today or the week's count is reached; past days count only when done (no penalty) |
| Water | day's hydration (contribution, not volume) ≥ profile water target |
| Protein at breakfast | ≥ 25 g protein logged as breakfast |
| Steps | Apple Health steps ≥ the habit's target (default: profile steps goal); no Health data = not done |
| Grid levels | 0 none · 1 ≤ ⅓ · 2 ≤ ⅔ · 3 more |
| Editorial | days in the last 7 (before today) with more than half the list done |
| Reminders | on the habit's days, only while not done, never 22:00–07:00, next 7 days |
