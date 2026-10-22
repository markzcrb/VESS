# Drink catalog: where each value comes from

Values are per 100 ml. "Earlier" = already in `DrinkPreset` before this
change (unchanged). "Type default" = the existing `DrinkType` share. Everything
marked **typical** is new, is shown in the app as "Typical values", and is
for a standard preparation. Defined in `VESS/Domain/Models/Drink.swift`.

| Drink | Serving | Counts toward water | kcal | Sugar g | Caffeine mg | Alcohol |
|---|---|---|---|---|---|---|
| Water | 250 | 100 % (type) | 0 | 0 | 0 | — |
| Sparkling water | 330 | 100 % (type) | 0 | 0 | 0 | — |
| Espresso | **30** | 80 % (type) | **9** | 0 | **212** (63 per shot) | — |
| Americano | **250** | 80 % (type) | **1** | 0 | **50** (double shot) | — |
| Cappuccino | **180** | 80 % (type) | **38** | **3.5** | **70** (double shot) | — |
| Latte | **300** | 80 % (type) | **54** | **5** | **42** (double shot) | — |
| Flat white | 240 | 79 % (earlier) | 46 | 4.5 | 54 | — |
| Drip coffee (stored as `blackCoffee`) | 200 | 90 % (earlier) | 1 | 0 | 40 | — |
| Cold brew | **250** | 80 % (type) | **2** | 0 | **45** | — |
| Black tea (stored as `tea`) | 250 | 90 % (type) | 1 | 0 | 20 | — |
| Green tea | **250** | 90 % (type) | **1** | 0 | **12** | — |
| Herbal tea | **250** | 90 % (type) | **1** | 0 | **0** | — |
| Juice | 250 | 85 % (type) | 45 | 9 | 0 | — |
| Soft drink | 330 | 70 % (type) | 42 | 10.6 | 10 (earlier) | — |
| Cola | **330** | 70 % (type) | **42** | **10.6** | **10** | — |
| Energy drink | **250** | 60 % (type) | **45** | **11** | **32** | — |
| Other drink | 250 | 75 % (type) | 0 | 0 | 0 | — |
| Beer | **330** | 0 % | **43** | 0 | 0 | **5 % ABV → 3.9 g** |
| Wine | **150** | 0 % | **83** | **0.8** | 0 | **12 % ABV → 9.5 g** |
| Spirit | **40** | 0 % | **231** | 0 | 0 | **40 % ABV → 31.6 g** |
| Cocktail | **150** | 0 % | **100** | **8** | 0 | **one 40 ml shot of 40 % in 150 ml → 8.4 g** |

Alcohol grams = % by volume × 0.789 g/ml (density of ethanol). A "drink" is
10 g of pure alcohol: a 330 ml beer is 13 g (1.3 drinks), a 150 ml wine
14 g (1.4), a 40 ml spirit 12.6 g (1.3).

## Notes

- "Soft drink" keeps its earlier 10 mg caffeine per 100 ml, which makes it
  the same as Cola. Open question: should a non-cola soft drink be 0 mg?
- Herbal tea uses the tea type's existing 90 %; it has no caffeine.
- The demo's green tea now uses the Green tea preset: 300 ml has 36 mg
  caffeine (it used the black-tea value before, 60 mg). Its 270 ml toward
  water (DATA.md) is unchanged.
