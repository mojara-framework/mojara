#!/usr/bin/env bash
# Validate the published Docker image's CLI, compiler and running HTTP application.
set -Eeuo pipefail

IMAGE="$1"
PLATFORM="$2"
TEST_DIR="$(mktemp -d)"
NAME="mojara-docker-smoke-$$"
chmod 777 "$TEST_DIR"
cleanup() {
  docker logs "$NAME" 2>/dev/null || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # Container-created files may be owned by Ubuntu's uid 1000, while
  # GitHub's ARM64 runner uses a different host uid. Clean within Docker.
  docker run --rm --platform "$PLATFORM" --user 0:0 \
    -v "$TEST_DIR:/workspace" --entrypoint /bin/sh "$IMAGE" \
    -c 'rm -rf -- /workspace/docker-smoke' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

docker run --rm --platform "$PLATFORM" "$IMAGE" version
docker run --rm --platform "$PLATFORM" "$IMAGE" doctor
docker run --rm --platform "$PLATFORM" --entrypoint watchexec "$IMAGE" --version

docker run --rm --platform "$PLATFORM" \
  -v "$TEST_DIR:/workspace" "$IMAGE" new docker-smoke
test -s "$TEST_DIR/docker-smoke/app.mojo"

docker run --rm --platform "$PLATFORM" \
  -v "$TEST_DIR:/workspace" -w /workspace/docker-smoke \
  "$IMAGE" build
test -x "$TEST_DIR/docker-smoke/build/app"

docker run --detach --name "$NAME" --platform "$PLATFORM" \
  -p 127.0.0.1:18893:8000 \
  -e MOJARA_HOST=0.0.0.0 -e MOJARA_PORT=8000 \
  -v "$TEST_DIR:/workspace" -w /workspace/docker-smoke \
  "$IMAGE" start --local >/dev/null

for attempt in $(seq 1 60); do
  if curl --fail --silent --show-error --max-time 2 \
    http://127.0.0.1:18893/health -o "$TEST_DIR/health.json" 2>/dev/null; then
    python3 - "$TEST_DIR/health.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as response:
    result = json.load(response)
assert result == {"status": "ok", "framework": "Mojara"}, result
print("PASS: Mojara Docker CLI, compiler, watcher, and HTTP application")
PY
    exit 0
  fi
  sleep 1
done

echo "Mojara Docker HTTP server did not become ready" >&2
exit 1
