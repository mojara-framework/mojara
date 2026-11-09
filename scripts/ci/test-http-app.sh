#!/usr/bin/env bash
# End-to-end smoke: native Mojo build, actual HTTP server, JSON and HTML.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SDK="$ROOT/build/full-integration/sdk"
DIR="$ROOT/build/full-integration/hello-ci"
export MOJARA_HOME="$SDK"
export LD_LIBRARY_PATH="$SDK/lib:${CONDA_PREFIX:-}/lib:${LD_LIBRARY_PATH:-}"
test -x "$SDK/bin/mojara"
test -s "$SDK/lib/mojo/mojara.mojoc"
cd "$ROOT/build/full-integration"
"$SDK/bin/mojara" new hello-ci
cd "$DIR"
test -f app.mojo
test -f mojara.project
test ! -e pixi.toml
"$SDK/bin/mojara" build
test -x build/app
PORT=18785
MOJARA_HOST=127.0.0.1 MOJARA_PORT="$PORT" "$SDK/bin/mojara" start --local > "$ROOT/build/full-integration/server.log" 2>&1 &
PID=$!
cleanup() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
}
trap cleanup EXIT
for i in $(seq 1 55); do
  if curl --fail --silent --show-error --max-time 1 "http://127.0.0.1:$PORT/health" > "$ROOT/build/full-integration/health.json" 2>/dev/null; then
    python3 - "$ROOT/build/full-integration/health.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d == {"status":"ok","framework":"Mojara"}, d
print("Native HTTP JSON validated:",d)
PY
    curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:$PORT/" > "$ROOT/build/full-integration/home.html"
    grep -qi 'Mojara' "$ROOT/build/full-integration/home.html"
    curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:$PORT/static/style.css" > "$ROOT/build/full-integration/style.css"
    test -s "$ROOT/build/full-integration/style.css"
    echo 'PASS: Full native framework + generated app + HTTP JSON + rendered HTML + static files'
    exit 0
  fi
  sleep 1
done
echo 'HTTP server startup failure:' >&2
tail -120 "$ROOT/build/full-integration/server.log" >&2 || true
exit 1
