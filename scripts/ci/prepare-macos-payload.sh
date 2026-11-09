#!/usr/bin/env bash
# Stage compiled Apple Silicon Mojara SDK for a relocatable Conda package.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ "$(uname -sm)" == "Darwin arm64" ]] || {
  echo "Only macOS Apple Silicon packages may use this staging script" >&2; exit 2;
}
SDK="$ROOT/build/full-integration/sdk"
STAGE="$ROOT/build/full-integration/package-payload/mojara"
test -s "$SDK/lib/mojo/mojara.mojoc"
test -x "$SDK/bin/mojara"
rm -rf -- "$STAGE"
mkdir -p "$STAGE"
cp -R "$SDK/." "$STAGE/"
# Ensure no Linux ELF binaries or accidental x86-64 bridges enter this release.
for lib in "$STAGE"/lib/*.dylib; do
  test -f "$lib"
  file "$lib" | grep -Eq 'Mach-O.*arm64|Mach-O.*universal'
  # Native dependencies are resolved relative to the installed prefix.
  # Remove the development Pixi prefix from the published Mach-O RPATH.
  if [[ -n "${CONDA_PREFIX:-}" ]]; then
    install_name_tool -delete_rpath "$CONDA_PREFIX/lib" "$lib" 2>/dev/null || true
  fi
done
file "$STAGE/bin/mojara" | grep -Eq 'Mach-O.*arm64|Mach-O.*universal'
mkdir -p "$STAGE/share/doc/mojara/licenses"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
cp "$ROOT/docs/THIRD_PARTY_LICENSES.md" "$STAGE/share/doc/mojara/licenses/THIRD_PARTY_LICENSES.md"
echo "PASS: Staged Apple Silicon native SDK for Conda."
