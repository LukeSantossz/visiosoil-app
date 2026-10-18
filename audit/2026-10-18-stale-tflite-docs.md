# Audit: stale-tflite-docs

Findings in `docs/architecture/soil-classification.md` where the document
describes the retired TFLite inference path as current, though ADR 0024 /
SPEC 0083 replaced it with the descriptor path.

- docs/architecture/soil-classification.md:61-62: claims spec.json is gitignored and assets/models/ holds only .gitkeep
- docs/architecture/soil-classification.md:581: mermaid diagram node "TFLite interpreter in isolate"
- docs/architecture/soil-classification.md:928: claims tflite_flutter ^0.12.1 is in pubspec.yaml
