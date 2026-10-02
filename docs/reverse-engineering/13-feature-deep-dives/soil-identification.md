# Deep dive — Soil identification

| Aspect | Reconstruction | Label |
|---|---|---|
| Objective | Turn one or more photos into a soil record with type, texture, health indicators and crop suggestions | CONFIRMED |
| Entry | Scanner tab; "Start Identifying" / "+" on My Soils; gallery button | CONFIRMED |
| Screen | `ScannerScreen` (VisionCamera preview, frame guide, flash toggle, gallery, remaining-scan badge, "Position the soil within the frame") → `UCropActivity` "Crop Soil" (rotate, scale) → progress overlay → `SoilDetailsScreen` | CONFIRMED |
| Components | camera view, shutter, scan-limit badge, cropper, progress bar, status text | CONFIRMED |
| State | `canScanMore`, `scansRemaining`, `capturedImage`, `imageUris`, progress %, `isProcessing` | HIGHLY LIKELY |
| Controller | screen handlers `handleTakePhoto`, `handleImageIdentification`, `openCropper` | HIGHLY LIKELY |
| Use case | `soilIdentificationService.identifySoilFromImages(images)` → `identifyWithGemini` | HIGHLY LIKELY |
| Data source | Gemini `generateContent`, inline image data | HIGHLY LIKELY |
| API | `generativelanguage.googleapis.com`, model from `primary_model` (default `gemini-2.5-flash`), backup on 503/429 | HIGHLY LIKELY |
| Persistence | `addSoilToCollection` → Zustand persist → AsyncStorage `@soil_collection`; quota → `@soil_identifier_user` | HIGHLY LIKELY |
| Entities | Soil, UserState | — |
| Rules | BR-01…05, BR-15…20 | — |
| Side effects | scan counter incremented; analytics events; image file kept for the record | HIGHLY LIKELY |
| Errors | model failure → "❌ Gemini AI identification failed" / "❌ Soil identification failed"; a non-soil image is **not** an error, and defaults are rendered | CONFIRMED (non-soil) |
| Dependencies | VisionCamera, image-crop-picker, Remote Config (models), Gemini SDK, stores | — |
| Output | navigation to the details of the new record | CONFIRMED |

## Call graph

```text
ScannerScreen.onShutter
→ guard canScanMore (premium || scansRemaining > 0) ── no ──▶ navigate(Paywall)
→ camera.takePhoto()
→ openCropper(photo)              (ImagePicker.openCropper → UCropActivity)
→ handleImageIdentification(uri)
  → readFile → base64             ("📸 Reading image from path", "🚀 Converting image(s) for Gemini AI")
  → soilIdentificationService.identifySoilFromImages([b64])
    → model names from Remote Config (fallback on timeout)
    → model(primary).generateContent([prompt, inlineData…])
        └─ on 503/429 → model(backup).generateContent(...)
    → parse text → JSON → soils[] → first
  → normalise + defaults (health 50, pH 7, Medium…)
  → collectionStore.addSoil(record); userStore.incrementScanCount()
→ navigate(SoilDetails, { soilId })
```

## Observed run (synthetic emulator scene, not soil)

1. "1 scan remaining" badge → shutter.
2. uCrop "Crop Soil" opened with the full frame → ✓.
3. Overlay "Identifying Soil… Analyzing image with AI": 1 % → 7 % → 15 % → 100 % "Complete!", with the result on screen 6–8 s after the crop was confirmed.
4. Details: **Unknown**, Medium Texture, 0 % match, health 50/100, fertility 50, water retention 50, pH 7, organic matter Medium, compaction 50, condition Fair, materials "Digital pixel data", description from the model ("The image consists of colored squares, which prevents a meaningful physical description…"), age estimate N/A.
5. Record saved to My Soils with tags "Vegetables", "Herbs"; badge now "0 scans remaining".

The model's description shows it recognised the input was not soil. For this image
the app rendered the defaults and saved the record anyway; whether a rejection branch
exists for other inputs is UNKNOWN.
