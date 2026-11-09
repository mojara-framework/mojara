#!/usr/bin/env bash
# Build a CI-only native Conda package, install it in a fresh Pixi home,
# and compile/run a real application. NEVER uploads to a public channel.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$ROOT/build/full-integration"
SDK="$WORK/sdk"
STAGE="$WORK/package-payload/mojara"
OUT="$WORK/ci-packages"
test -s "$SDK/lib/mojo/mojara.mojoc"
test -x "$SDK/bin/mojara"
mkdir -p "$STAGE" "$OUT"
cp -a "$SDK/." "$STAGE/"
# All native libraries live under opt/mojara/lib while their Conda runtime
# dependencies live under prefix/lib (or prefix/lib/mariadb for Connector/C).
# Use relative RUNPATHs so a package
# remains relocatable across Pixi and Conda environment directories.
command -v patchelf >/dev/null || { echo 'patchelf is required for packaging' >&2; exit 2; }
while IFS= read -r -d '' native; do
  patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../lib:$ORIGIN/../../../lib/mariadb' "$native"
done < <(find "$STAGE/lib" -type f -name '*.so*' -print0)
# Preserve the Mojo compiler runtime lookup metadata on the native CLI.
# Rattler relocates that executable during package construction; overriding
# its RUNPATH here breaks libKGENCompilerRTShared.so resolution.
# An absolute path to the CI compiler or build directory must not escape
# into a distributable artifact.
if command -v readelf >/dev/null; then
  while IFS= read -r -d '' native; do
    dynamic="$(readelf -d "$native" | grep -E 'RPATH|RUNPATH' || true)"
    case "$dynamic" in
      *"/home/runner/"*|*"/tmp/mojara"*|*"/.pixi/envs/default/"*)
        echo "Non-relocatable native RUNPATH: $native: $dynamic" >&2
        exit 1
        ;;
    esac
  done < <(find "$STAGE/lib" -type f -name '*.so*' -print0)
fi
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
mkdir -p "$STAGE/share/doc/mojara/licenses"
cp "$ROOT/docs/THIRD_PARTY_LICENSES.md" "$STAGE/share/doc/mojara/licenses/THIRD_PARTY_LICENSES.md"
printf 'CI candidate only; not a production release. Native extension and full release qualification pending.\n' > "$STAGE/CI-NOT-A-RELEASE.txt"

# The published binary SDK is NOT used. The source-only archive was checked
# by SHA256 in bootstrap-source.sh and this entire SDK compiled on the runner.
pixi global install rattler-build -c conda-forge
rattler-build build -r "$ROOT/packaging/ci/recipe.yaml" \
  -c https://conda.modular.com/max/ -c conda-forge \
  --output-dir "$OUT"
PACKAGE="$(find "$OUT" -type f -name 'mojara-ci-smoke-*.conda' -print -quit)"
test -n "$PACKAGE"
file "$PACKAGE"
echo "Locally-built native candidate: $PACKAGE"
echo "Package SHA256:"
sha256sum "$PACKAGE"
FRESH="$WORK/fresh-pixi"
mkdir -p "$FRESH"
export PIXI_HOME="$FRESH"
pixi global install --path "$PACKAGE" \
  -c https://conda.modular.com/max/ -c conda-forge
CLI="$FRESH/bin/mojara"
test -x "$CLI"
"$CLI" version
"$CLI" doctor
bash "$ROOT/scripts/ci/verify-installed-links.sh" "$FRESH"
echo "Fresh package contents:"
file "$FRESH"/envs/*/opt/mojara/bin/mojara
TEST="$WORK/fresh-app"
cd "$WORK"
"$CLI" new fresh-app
cd "$TEST"
"$CLI" build
test -x build/app
MOJARA_HOST=127.0.0.1 MOJARA_PORT=18787 "$CLI" start --local > "$WORK/fresh-install-server.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true' EXIT
for i in $(seq 1 40); do
  if curl -fsS --max-time 1 "http://127.0.0.1:18787/health" > "$WORK/fresh-install-health.json" 2>/dev/null; then
    python3 - "$WORK/fresh-install-health.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['status']=='ok' and d['framework']=='Mojara',d
print('PASS: Fresh Pixi home installed source-built native Mojara package; native application served HTTP.',d)
PY
    exit 0
  fi
  sleep 1
done
tail -120 "$WORK/fresh-install-server.log" >&2
echo "Fresh package HTTP app never became ready" >&2
exit 1
