#!/usr/bin/env bash
# Orchestrates the full ML pipeline: train -> evaluate -> export.
# Usage: bash scripts/train_and_export.sh [version]
#   version: Model version string (default: v1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ML_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-v1}"

cd "$ML_ROOT"

PYTHON="${ML_ROOT}/.venv/bin/python"
if [ ! -f "$PYTHON" ]; then
    echo "Error: Virtual environment not found. Run 'make setup' first."
    exit 1
fi

echo "----------------------------------------"
echo "VisioSoil ML Pipeline - ${VERSION}"
echo "----------------------------------------"

echo ""
echo "[1/3] Training..."
$PYTHON -m src.train --version "$VERSION"

echo ""
echo "[2/3] Evaluating..."
$PYTHON -m src.evaluate --version "$VERSION"

echo ""
echo "[3/3] Exporting to TFLite..."
$PYTHON -m src.export --version "$VERSION"

echo ""
echo "----------------------------------------"
echo "Pipeline complete. Artifacts in models/${VERSION}/"
echo "----------------------------------------"
echo ""
echo "Next step: bash scripts/deploy_to_app.sh ${VERSION}"
