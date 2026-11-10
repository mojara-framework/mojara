#!/usr/bin/env bash
# Produce an unpublished native osx-arm64 Mojara package for qualification.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$ROOT/build/full-integration"
OUT="$WORK/macos-packages"
bash "$ROOT/scripts/ci/prepare-macos-payload.sh"
pixi global install rattler-build -c conda-forge
rattler-build build -r "$ROOT/packaging/macos/recipe.yaml" \
  -c https://conda.modular.com/max/ -c conda-forge --output-dir "$OUT"
PKG="$(find "$OUT" -type f -name 'mojara-1.2.9-*.conda' -print -quit)"
test -s "$PKG" || { echo "macOS Mojara package not produced" >&2; exit 1; }
file "$PKG"
shasum -a 256 "$PKG"
echo "MACOS_PACKAGE=$PKG"
