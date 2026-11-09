#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64|Linux/aarch64|Darwin/arm64) ;;
  *) echo "Unsupported host: $(uname -s)/$(uname -m)" >&2; exit 2 ;;
esac
mkdir -p build/bin
flags=()
[[ "$(uname -s)" == "Linux" ]] && flags+=("-Xlinker=-ldl")
mojo build source/cli/mojara_cli.mojo -o build/bin/mojara "${flags[@]}"
./build/bin/mojara version
