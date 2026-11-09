#!/usr/bin/env bash
# Confirm that all installed ELF components resolve their native dependencies.
# Checks the installed package, not the source compiler environment.
set -Eeuo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: verify-installed-links.sh PIXI_HOME" >&2
  exit 2
fi
command -v ldd >/dev/null || { echo "ldd is required to verify Linux packages" >&2; exit 2; }
PIXI_ENV_HOME="$1/envs"
test -d "$PIXI_ENV_HOME" || { echo "Missing Pixi environments: $PIXI_ENV_HOME" >&2; exit 2; }
SDK_BIN="$(find "$PIXI_ENV_HOME" -path '*/opt/mojara/bin/mojara' -type f -print -quit)"
test -n "$SDK_BIN" || { echo "Installed native Mojara CLI not found" >&2; exit 1; }
SDK_ROOT="$(cd "$(dirname "$SDK_BIN")/.." && pwd -P)"
test -d "$SDK_ROOT/lib" || { echo "Missing installed native library directory" >&2; exit 1; }

checked=0
while IFS= read -r -d '' binary; do
  # Clear local environment overrides; the loader must find dependencies
  # through the installed package's own relative paths and runtime packages.
  if ! dependencies="$(env -u LD_LIBRARY_PATH ldd "$binary" 2>&1)"; then
    echo "Cannot resolve native dependencies for: $binary" >&2
    echo "$dependencies" >&2
    exit 1
  fi
  if grep -q 'not found' <<< "$dependencies"; then
    echo "Missing native dependencies in installed package: $binary" >&2
    echo "$dependencies" >&2
    exit 1
  fi
  checked=$((checked + 1))
done < <(find "$SDK_ROOT/lib" "$SDK_ROOT/bin" -type f \( -name '*.so*' -o -name mojara \) -print0)

if (( checked < 2 )); then
  echo "Native component inventory unexpectedly empty" >&2
  exit 1
fi
echo "PASS: $checked installed native ELF components have no unresolved shared libraries"
