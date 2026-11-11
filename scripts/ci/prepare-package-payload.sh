#!/usr/bin/env bash
# Stage the source-built native SDK as a relocatable Conda package payload.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
MODE="${1:-ci}"
case "$MODE" in ci|release) ;; *) echo "Usage: $0 ci|release" >&2; exit 2;; esac
SDK="$ROOT/build/full-integration/sdk"
STAGE="$ROOT/build/full-integration/package-payload/mojara"
test -s "$SDK/lib/mojo/mojara.mojoc"
test -x "$SDK/bin/mojara"
command -v patchelf >/dev/null || { echo "patchelf required" >&2; exit 2; }
command -v readelf >/dev/null || { echo "readelf required" >&2; exit 2; }
rm -rf -- "$STAGE"
mkdir -p "$STAGE"
cp -a "$SDK/." "$STAGE/"

# The native Linux CLI needs the compiler runtime from the installed
# Conda prefix. Use a relocatable RPATH, not a build-machine path.
if [[ "$(uname -s)" == "Linux" ]]; then
  patchelf --force-rpath --set-rpath '$ORIGIN/../../../lib' "$STAGE/bin/mojara"
fi

# The libraries are below prefix/opt/mojara/lib; Conda runtime libraries
# are installed under prefix/lib or prefix/lib/mariadb.
while IFS= read -r -d '' native; do
  patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../lib:$ORIGIN/../../../lib/mariadb' "$native"
done < <(find "$STAGE/lib" -type f -name '*.so*' -print0)
# Let rattler-build relocate the Mojo CLI's compiler runtime references.
# Overwriting the CLI's RUNPATH causes libKGENCompilerRTShared.so failures.
while IFS= read -r -d '' native; do
  dynamic="$(readelf -d "$native" | grep -E 'RPATH|RUNPATH' || true)"
  case "$dynamic" in
    *"/home/runner/"*|*"/.pixi/envs/"*|*"/tmp/mojara"*)
      echo "Non-relocatable shared-library RUNPATH: $native: $dynamic" >&2
      exit 1
      ;;
  esac
done < <(find "$STAGE/lib" -type f -name '*.so*' -print0)
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
mkdir -p "$STAGE/share/doc/mojara/licenses"
cp "$ROOT/docs/THIRD_PARTY_LICENSES.md" "$STAGE/share/doc/mojara/licenses/THIRD_PARTY_LICENSES.md"
if [[ "$MODE" == ci ]]; then
  printf 'Unpublished CI candidate; not a production release.\n' > "$STAGE/CI-NOT-A-RELEASE.txt"
fi
printf 'Prepared %s payload from native source for %s\n' "$MODE" "$(uname -sm)"
