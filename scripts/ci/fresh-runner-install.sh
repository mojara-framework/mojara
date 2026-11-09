#!/usr/bin/env bash
# Test a CI-built Mojara package on a NEW GitHub runner without C build tools.
# This intentionally avoids depending on packages installed by build job.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
DOWN="$ROOT/build/fresh-package-download"
PKG="$(find "$DOWN" -name 'mojara-ci-smoke-*.conda' -type f -print -quit)"
test -n "$PKG" || { echo 'Missing candidate package artifact' >&2; exit 2; }
WORK="$ROOT/build/fresh-package-verify"
mkdir -p "$WORK"
export PIXI_HOME="$WORK/pixi"
pixi global install --path "$PKG" \
  -c https://conda.modular.com/max/ \
  -c conda-forge
CLI="$PIXI_HOME/bin/mojara"
test -x "$CLI"
"$CLI" version
"$CLI" doctor
file "$PIXI_HOME"/envs/*/opt/mojara/bin/mojara
cd "$WORK"
"$CLI" new isolated-smoke
cd isolated-smoke
"$CLI" build
test -x build/app
MOJARA_HOST=127.0.0.1 MOJARA_PORT=18789 "$CLI" start --local > "$WORK/isolated-server.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true' EXIT
for i in $(seq 1 40); do
  if curl -fsS --max-time 1 http://127.0.0.1:18789/health > "$WORK/isolated-health.json" 2>/dev/null; then
    python3 - "$WORK/isolated-health.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d == {"status":"ok","framework":"Mojara"},d
print("PASS: Isolated native package install, app compilation, HTTP health on fresh runner")
PY
    exit 0
  fi
  sleep 1
done
tail -100 "$WORK/isolated-server.log" >&2 || true
exit 1
