#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64|Linux/aarch64|Darwin/arm64) ;;
  *) echo "Unsupported host: $(uname -s)/$(uname -m)" >&2; exit 2 ;;
esac
mkdir -p build/bin
flags=()
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    # A release built with the runner's CPU defaults may SIGILL on another
    # x86-64 machine. Use the baseline x86-64 instruction set.
    flags+=("--target-cpu=x86-64" "-Xlinker=-ldl")
    ;;
  Linux/aarch64)
    # Avoid compiling a package for the particular ARM runner's CPU model.
    flags+=("--target-cpu=generic" "-Xlinker=-ldl")
    ;;
esac
# Apple's Bash 3.2 treats expansion of an empty array as unbound with set -u.
# Build macOS without Linux-only linker and CPU flags.
if [[ "$(uname -s)" == "Darwin" ]]; then
  mojo build source/cli/mojara_cli.mojo -o build/bin/mojara
else
  mojo build source/cli/mojara_cli.mojo -o build/bin/mojara "${flags[@]}"
fi
./build/bin/mojara version
