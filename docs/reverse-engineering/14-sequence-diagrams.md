# 14 — Sequence diagrams

Participants follow the reconstructed modules of [04](04-module-dependencies.md).
Arrows marked `(I)` are inferred and the others are observed or highly likely.

## 1. Cold start

```mermaid
sequenceDiagram
    participant OS as Android
    participant CP as Content providers
    participant RN as RN host (Hermes)
    participant ST as Zustand stores
    participant RC as Remote Config
    participant PUR as RevenueCat
    participant NAV as RootNavigator
    OS->>CP: create (Notifee, Firebase, Crashlytics, ML Kit, startup, pairip)
    OS->>RN: MainApplication / MainActivity
    RN->>ST: rehydrate from AsyncStorage
    RN->>RC: fetchAndActivate (timeout)
    RC-->>RN: models, limits (or fallback defaults)
    RN->>PUR: configure + identify user + sync purchases
    PUR-->>ST: isPremium / expirationDate
    RN->>NAV: initial route
    alt onboarding incomplete
        NAV-->>RN: OnboardingScreen
    else completed
        NAV-->>RN: MainTabs (My Soils)
    end
```

## 2. Identification (happy path and the non-soil path)

```mermaid
sequenceDiagram
    actor U as User
    participant S as ScannerScreen
    participant CAM as VisionCamera
    participant CR as uCrop
    participant ID as identification service
    participant RC as Remote Config
    participant G as Gemini API
    participant ST as Stores
    U->>S: tap shutter
    S->>ST: canScanMore?
    alt no scans left and online
        S-->>U: present Paywall
    else no scans left and offline
        S-->>U: back to My Soils, no message (diagram 5)
    else scans left
        S->>CAM: takePhoto()
        CAM-->>S: file
        S->>CR: openCropper(file)
        U->>CR: confirm ✓
        CR-->>S: cropped file
        S-->>U: overlay "Identifying Soil…" (progress)
        S->>ID: identifySoilFromImages([base64])
        ID->>RC: primary_model
        ID->>G: generateContent(prompt + inlineData)
        alt 503 / 429
            G-->>ID: error
            ID->>G: generateContent(backup_model)
        end
        G-->>ID: text (JSON)
        ID->>ID: parse → soils[0] → apply defaults
        Note over ID: non-soil photo still yields a record<br/>(Unknown, 0 %, health 50, pH 7)
        ID-->>S: soil
        S->>ST: addSoil(soil); incrementScanCount()
        S-->>U: navigate SoilDetails
    end
```

## 3. Chat turn

```mermaid
sequenceDiagram
    actor U as User
    participant C as SoilChatScreen
    participant CTX as Chat context
    participant CS as chat service
    participant G as Gemini API
    U->>C: tap quick prompt / send
    C->>CTX: append user message (optimistic) + typing
    CTX->>CS: send(history, soil)
    CS->>G: generateContent(flash)
    alt flash unavailable
        CS->>G: generateContent(pro)
    end
    alt success
        G-->>CS: reply
    else any error
        CS-->>CTX: "I'm having trouble processing that…"
    end
    CTX->>CTX: saveChatHistory(soilId)
    CTX-->>C: render AI bubble
```

## 4. Purchase from the paywall

```mermaid
sequenceDiagram
    actor U as User
    participant P as PaywallScreen
    participant PUR as purchases service
    participant RCAT as RevenueCat
    participant GP as Play Billing
    P->>PUR: loadOfferings()
    PUR->>RCAT: getOfferings()
    RCAT-->>P: weekly (trial), yearly, lifetime
    U->>P: TRY 3-DAY FREE
    P->>PUR: purchasePackage(weekly)
    PUR->>RCAT: purchase
    RCAT->>GP: launch billing flow
    alt user completes
        GP-->>RCAT: purchase token
        RCAT-->>PUR: CustomerInfo (premium active)
        PUR-->>P: isPremium = true → close
    else user cancels
        GP-->>P: cancelled → stay on paywall
    end
```

## 5. Shutter at zero scans while offline (observed)

```mermaid
sequenceDiagram
    actor U as User
    participant S as ScannerScreen
    participant P as PaywallScreen
    participant RCAT as RevenueCat
    U->>S: tap shutter (0 scans, no network)
    S->>P: present
    P->>RCAT: getOfferings()
    RCAT-->>P: error / no offering
    P-->>S: dismiss (I)
    S-->>U: back on My Soils, no message
```
