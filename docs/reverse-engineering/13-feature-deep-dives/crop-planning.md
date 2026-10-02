# Deep dive — Crop planning ("Grow Anything Coach")

| Aspect | Reconstruction | Label |
|---|---|---|
| Objective | Suggest what to grow on a given soil and give growing facts | CONFIRMED |
| Entry | details "Browse Compatible Crops"; onboarding slide 2 promises it | CONFIRMED |
| Screens | `CropPlanningScreen` (title "Grow Anything Coach · Optimized for {soilType}", search, category chips All/Vegetables/Fruits/Grains/…, season chips All/Spring/Summer/Fall/…, "41 crops found · Sorted by compatibility", 2-column cards) → `CropDetailsScreen` (category and family chips, compatibility warning, growth time, avg yield, sunlight, water, nitrogen need, preferred soil types, pH range, best seasons) | CONFIRMED |
| State | search text, selected category, selected season (local) | HIGHLY LIKELY |
| Use case | `getCropsForSoilType`, `getCropsByCategory`, `searchCrops`, `getSoilCompatibilityScore`, `getSoilCompatibilityColor` | HIGHLY LIKELY |
| Data source | a static catalogue bundled in JS | HIGHLY LIKELY (works offline, no network hosts for crops) |
| Persistence | none | — |
| Rules | BR-23, BR-24 | — |
| Errors | none; an unknown soil gives a uniform 50 % | CONFIRMED |
| Output | ranked list and a details page | CONFIRMED |

## Call graph

```text
SoilDetails → navigate(CropPlanning, { soilType })
CropPlanningScreen
→ crops = CROPS.filter(category, season, search)
→ score(crop) = compatibility(soilType, crop.preferredSoilTypes, crop.phRange)
→ sort by score desc → render
card → navigate(CropDetails, { cropId, soilType })
```

## Content-quality observations

- Tomato "Avg Yield 25-30 kg per plant" is shown with no source and no growing system. **CONFIRMED** displayed (E-O). Its plausibility was not assessed here; the point for VisioSoil is that a numeric agronomic claim needs a cited source and scope.
- The onboarding says "browse 50+ crops"; the catalogue showed 41. **CONFIRMED** (E-O).
- Soil vocabulary is USDA-style English (Loam, Sandy Loam, Silt).
