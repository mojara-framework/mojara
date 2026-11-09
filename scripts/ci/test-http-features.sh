#!/usr/bin/env bash
# End-to-end signed cookies, upload, WS protocol and bounded HTTP load test.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SDK="$ROOT/build/full-integration/sdk"
WORK="$ROOT/build/full-integration/http-features"
export MOJARA_HOME="$SDK"
export LD_LIBRARY_PATH="$SDK/lib:${CONDA_PREFIX:-}/lib:${LD_LIBRARY_PATH:-}"
mkdir -p "$WORK/private_uploads"
chmod 700 "$WORK/private_uploads"
mojo build -I "$SDK/lib/mojo" "$ROOT/tests/integration/http_features.mojo" \
  -o "$WORK/app" -Xlinker=-ldl
cd "$WORK"
export MOJARA_HOST=127.0.0.1
export MOJARA_PORT=18786
# This enables Mojara's EXISTING development WebSocket handler for this probe;
# the test does not claim validation of a production custom WS application API.
export MOJARA_DEV_RELOAD=1
CONDA_PREFIX="$SDK" ./app > "$WORK/server.log" 2>&1 &
PID=$!
cleanup() {
  if kill -0 "$PID" 2>/dev/null; then kill -TERM "$PID" 2>/dev/null || true; fi
  wait "$PID" 2>/dev/null || true
}
trap cleanup EXIT
READY=0
for i in $(seq 1 60); do
  if curl -fsS --max-time 1 "http://127.0.0.1:$MOJARA_PORT/health" > /dev/null 2>&1; then
    READY=1; break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo 'Server exited during startup:' >&2
    cat "$WORK/server.log" >&2
    exit 1
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then cat "$WORK/server.log" >&2; exit 1; fi
python3 "$ROOT/tests/integration/http_features_probe.py" --port "$MOJARA_PORT" --work "$WORK"
# This checks bounded process exit after all requests completed. It does NOT
# claim no-loss handling of active requests during graceful shutdown.
kill -TERM "$PID" 2>/dev/null || true
for i in $(seq 1 60); do
  if ! kill -0 "$PID" 2>/dev/null; then break; fi
  sleep 0.1
done
if kill -0 "$PID" 2>/dev/null; then
  kill -KILL "$PID" 2>/dev/null || true
  echo 'FAIL: server did not exit within six seconds after SIGTERM' >&2
  exit 1
fi
wait "$PID" || [ "$?" -eq 143 ]
trap - EXIT
echo 'PASS: HTTP feature suite and bounded server termination'
