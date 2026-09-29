#!/usr/bin/env bash
# Promotes a release's spec.json into the Flutter app (ADR 0012, SPEC 0082).
# Usage: bash scripts/deploy_to_app.sh [version]
#   version: Dataset version the release was fitted on (default: v1)
#
# The v1 classifier is the descriptor path (ADR 0024): the contract is the
# whole model, so there is no .tflite to promote. The commit that adds the
# promoted file is the release record, and its subject names the dataset
# version and the headline metrics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ML_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ROOT="$(cd "$ML_ROOT/.." && pwd)"
VERSION="${1:-v1}"

SPEC_SRC="${ML_ROOT}/models/${VERSION}/release/spec.json"
ASSETS_DIR="${APP_ROOT}/assets/models"

echo "Promoting the ${VERSION} release to the Flutter app..."

if [ ! -f "$SPEC_SRC" ]; then
    echo "Error: no release at ${SPEC_SRC}"
    echo "Fit one first: cd ml && python -m src.release --version ${VERSION} --model-version <version>"
    exit 1
fi

if [ ! -d "$ASSETS_DIR" ]; then
    echo "Error: Flutter assets directory not found at ${ASSETS_DIR}"
    exit 1
fi

cp "$SPEC_SRC" "${ASSETS_DIR}/spec.json"

echo "Promoted:"
echo "  ${SPEC_SRC} -> ${ASSETS_DIR}/spec.json"
