#!/usr/bin/env bash
# Install a macOS Mojara candidate on a separate clean Apple Silicon runner.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ "$(uname -sm)" == "Darwin arm64" ]] || exit 2
DOWN="$ROOT/build/macos-package-download"
PKG="$(find "$DOWN" -type f -name 'mojara-1.2.10-*.conda' -print -quit)"
test -s "$PKG"
WORK="$ROOT/build/macos-fresh-install"
mkdir -p "$WORK"
export PIXI_HOME="$WORK/pixi"
pixi global install --path "$PKG" -c https://conda.modular.com/max/ -c conda-forge
CLI="$PIXI_HOME/bin/mojara"
"$CLI" version
"$CLI" doctor
cd "$WORK"
"$CLI" new macos-package-smoke
cd macos-package-smoke
"$CLI" build
test -x build/app
MOJARA_HOST=127.0.0.1 MOJARA_PORT=18882 "$CLI" start --local > "$WORK/server.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
for i in $(seq 1 45); do
  if curl -fsS --max-time 1 http://127.0.0.1:18882/health -o "$WORK/health.json" 2>/dev/null; then
    python3 - "$WORK/health.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
assert value == {"status": "ok", "framework": "Mojara"}, value
print("PASS: Native Apple Silicon package installed on clean host and served HTTP")
PY
    exit 0
  fi
  sleep 1
done
tail -100 "$WORK/server.log" >&2
exit 1
