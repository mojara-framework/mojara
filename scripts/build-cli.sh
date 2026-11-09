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
mojo build source/cli/mojara_cli.mojo -o build/bin/mojara "${flags[@]}"
./build/bin/mojara version
