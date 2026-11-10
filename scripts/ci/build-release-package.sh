#!/usr/bin/env bash
# Package the precompiled source-built Mojara SDK for the current Linux CPU.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$ROOT/build/full-integration"
OUT="$WORK/release-packages"
mkdir -p "$OUT"
bash "$ROOT/scripts/ci/prepare-package-payload.sh" release
test ! -e "$WORK/package-payload/mojara/CI-NOT-A-RELEASE.txt"
pixi global install rattler-build -c conda-forge
rattler-build build -r "$ROOT/packaging/conda/recipe.yaml" \
  -c https://conda.modular.com/max/ -c conda-forge --output-dir "$OUT"
PACKAGE="$(find "$OUT" -type f -name 'mojara-1.2.9-*.conda' -print -quit)"
test -s "$PACKAGE" || { echo "Missing Mojara release package" >&2; exit 1; }
bash "$ROOT/scripts/ci/audit-release-abi.sh" "$PACKAGE"
file "$PACKAGE"
sha256sum "$PACKAGE"
echo "RELEASE_PACKAGE=$PACKAGE"
