# Deep dive — Soil calculator

| Aspect | Reconstruction | Label |
|---|---|---|
| Objective | How much soil, how many bags and what it costs, for a raised bed or a planter | CONFIRMED |
| Entry | Calculator tab | CONFIRMED |
| Screen | unit toggle (Imperial ft/in · Metric m/cm), shape cards (Rectangular "Raised Bed" L×W×D · Circular "Planter" π×R²×D), dimension fields, "Calculate Volume", result card ("Volume Needed": cu ft, ≈ cu yd, ≈ L, ≈ gal), "Recommended Soil Types" product cards (bags, est. cost, "best for" tags) | CONFIRMED |
| State | unit system, shape, inputs, validation errors, result (local) | CONFIRMED (UI) |
| Use case | `calculateRectangularVolume`, `calculateCircularVolume`, `convertDepthToFeet`, `convertVolume`, `estimateBagsNeeded`, `validateDepth`, `canCalculate` | HIGHLY LIKELY |
| Data source | static product catalogue (topsoil, raised-bed mix, organic potting mix, vegetable garden soil, cactus mix) with bag size, price range and retailer search URLs | HIGHLY LIKELY |
| Rules | BR-25…28 | — |
| Errors | inline validation "Value must be at least 2.5" (metric) | CONFIRMED |
| Output | volume in four units, bag counts, USD cost ranges | CONFIRMED |

## Worked check

Input 3 m × 3 m × 30 cm → 2.7 m³ = 2 700 L = 95.35 cu ft = 3.53 cu yd = 713.26 gal.
Topsoil: 53 bags of 2 cu ft (95.35 / 2 → 48 bags, so the app adds about 10 %
headroom, INFERRED), est. $317.47–$396.84 (53 × $5.99–$7.49, INFERRED unit
prices). Raised bed mix: 35 bags of 3 cu ft. **CONFIRMED** outputs (E-O).

## Defects observed

- The metric minimum of 2.5 m on length and width rejects ordinary planters (e.g. 2 m × 1 m).
- Imperial-only bag sizes and USD costs are shown in metric mode and on a BRL store.
