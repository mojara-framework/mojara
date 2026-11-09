#!/usr/bin/env bash
# Run Mojara's supported Linux x86-64 CLI on an Intel Mac with Docker Desktop.
set -Eeuo pipefail

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker Desktop must be installed and running." >&2
  exit 1
fi

IMAGE="${MOJARA_DOCKER_IMAGE:-ghcr.io/mojara-framework/mojara:1.2.7}"
HOST_PORT="${MOJARA_DOCKER_PORT:-8000}"
if [[ ! "$HOST_PORT" =~ ^[0-9]+$ ]] || (( HOST_PORT < 1 || HOST_PORT > 65535 )); then
  echo "MOJARA_DOCKER_PORT must be an integer between 1 and 65535." >&2
  exit 2
fi

tty=()
if [[ -t 0 && -t 1 ]]; then
  tty=(-t)
fi

port_args=()
case "${1:-}" in
  dev|start) port_args=(-p "127.0.0.1:${HOST_PORT}:8000") ;;
esac

exec docker run --rm --init -i "${tty[@]}" \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -w /workspace \
  -e MOJARA_HOST=0.0.0.0 \
  -e MOJARA_PORT=8000 \
  "${port_args[@]}" \
  "$IMAGE" "$@"
