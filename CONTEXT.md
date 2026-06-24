# VisioSoil

Geolocated soil texture analysis for agronomists: photograph a soil sample, capture location, classify its texture on-device, and surface guidance for the sample.

## Language

**Soil Record**:
A single geolocated soil sample captured in the field — its photo, coordinates, address, timestamp, and (once classified) texture class and confidence.
_Avoid_: entry, item, document

**Soil Texture Class**:
One of the five texture categories the on-device classifier assigns to a Soil Record.
_Avoid_: soil type, soil category, soil kind

**Management Tip** (pt-BR UI: "dica de manejo"):
An advisory, non-prescriptive piece of soil-management guidance surfaced for a Soil Record, derived from its texture class and location. Educational guidance the agronomist weighs — never a field instruction to execute blindly.
_Avoid_: recommendation, instruction, prescription

**Advisory** (vs **Prescription**):
The stance of all guidance the app gives: it informs and cites sources; it does not prescribe a specific field action. A Prescription — a specific corrective/fertilization/tillage directive — is explicitly out of scope until the app collects the agronomic inputs (crop, season, soil chemistry) that would justify one.
_Avoid_: using "recommendation" loosely to mean either
