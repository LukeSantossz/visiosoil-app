#!/usr/bin/env bash
# Deploys trained TFLite model and spec.json to the Flutter app assets.
# Usage: bash scripts/deploy_to_app.sh [version]
#   version: Model version string (default: v1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ML_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ROOT="$(cd "$ML_ROOT/.." && pwd)"
VERSION="${1:-v1}"

MODEL_DIR="${ML_ROOT}/models/${VERSION}"
TFLITE_SRC="${MODEL_DIR}/model.tflite"
SPEC_SRC="${MODEL_DIR}/spec.json"
ASSETS_DIR="${APP_ROOT}/assets/models"

echo "Deploying model ${VERSION} to Flutter app..."

# Validate source files exist
if [ ! -f "$TFLITE_SRC" ]; then
    echo "Error: TFLite model not found at ${TFLITE_SRC}"
    echo "Run the training pipeline first: bash scripts/train_and_export.sh ${VERSION}"
    exit 1
fi

if [ ! -f "$SPEC_SRC" ]; then
    echo "Error: spec.json not found at ${SPEC_SRC}"
    exit 1
fi

# Validate target directory exists
if [ ! -d "$ASSETS_DIR" ]; then
    echo "Error: Flutter assets directory not found at ${ASSETS_DIR}"
    exit 1
fi

# Copy files
cp "$TFLITE_SRC" "${ASSETS_DIR}/soil_classifier.tflite"
cp "$SPEC_SRC" "${ASSETS_DIR}/spec.json"

echo "Deployed:"
echo "  ${TFLITE_SRC} -> ${ASSETS_DIR}/soil_classifier.tflite"
echo "  ${SPEC_SRC} -> ${ASSETS_DIR}/spec.json"
echo ""
echo "Done. Run 'flutter build apk --release' to verify the build."
