#!/usr/bin/env bash
set -Eeuo pipefail
echo "Host: $(uname -srm)"
case "$(uname -s)/$(uname -m)" in
 Linux/x86_64) echo "Linux x86-64 source test" ;;
 Linux/aarch64) echo "Linux ARM64 source test (experimental)" ;;
 Darwin/arm64) echo "macOS Apple Silicon source test (experimental)" ;;
 *) echo "Unsupported host" >&2; exit 2 ;;
esac
mojo --version
