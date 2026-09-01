#!/usr/bin/env bash
# Orchestrates the full ML pipeline: cross-validate -> report -> export.
# Usage: bash scripts/train_and_export.sh [version] [arm]
#   version: Dataset version string (default: v1)
#   arm:     Experimental arm (default: cnn)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ML_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-v1}"
ARM="${2:-cnn}"

cd "$ML_ROOT"

PYTHON="${ML_ROOT}/.venv/bin/python"
if [ ! -f "$PYTHON" ]; then
    echo "Error: Virtual environment not found. Run 'make setup' first."
    exit 1
fi

echo "----------------------------------------"
echo "VisioSoil ML Pipeline - ${VERSION} / ${ARM}"
echo "----------------------------------------"

echo ""
echo "[1/3] Cross-validating every repeat and fold..."
$PYTHON -m src.crossval --version "$VERSION" --arm "$ARM"

echo ""
echo "[2/3] Reporting..."
$PYTHON -m src.evaluate --version "$VERSION" --arm "$ARM"

echo ""
echo "[3/3] Exporting to TFLite..."
# src.export reads models/<version>/model.keras. The protocol produces one model
# per fold per repeat and does not decide which of them ships: promoting a model
# is the release decision, and it belongs to the experiment that makes it, not to
# the evaluation protocol. The script says so rather than picking one.
if [ ! -f "models/${VERSION}/model.keras" ] && [ ! -f "models/${VERSION}/model.h5" ]; then
    echo "No model promoted to models/${VERSION}/model.keras."
    echo "Cross-validation produced one model per fold under"
    echo "  models/${VERSION}/${ARM}/repeat-<r>/fold-<i>/model.keras"
    echo "Which one ships is a release decision this protocol does not make."
    exit 0
fi
$PYTHON -m src.export --version "$VERSION"

echo ""
echo "----------------------------------------"
echo "Pipeline complete. Artifacts in models/${VERSION}/${ARM}/"
echo "----------------------------------------"
echo ""
echo "Next step: bash scripts/deploy_to_app.sh ${VERSION}"
