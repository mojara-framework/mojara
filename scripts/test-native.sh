#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CC="${CC:-cc}"
FLAGS=(-std=gnu11 -O2 -Wall -Wextra -Werror -pthread)
BUILD="$ROOT/build/native-tests"
mkdir -p "$BUILD"
echo "Testing native Mojara C bridges on $(uname -s) $(uname -m)"
"$CC" "${FLAGS[@]}" "$ROOT/source/native/web.c" "$ROOT/source/native/multi_upload.c" "$ROOT/tests/native/test_web.c" -o "$BUILD/test_web"
"$BUILD/test_web"
"$CC" "${FLAGS[@]}" "$ROOT/source/native/web.c" "$ROOT/source/native/multi_upload.c" "$ROOT/tests/native/test_multi_upload.c" -o "$BUILD/test_multi_upload"
"$BUILD/test_multi_upload"
"$CC" "${FLAGS[@]}" "$ROOT/source/native/metrics.c" "$ROOT/tests/native/test_metrics.c" -o "$BUILD/test_metrics"
"$BUILD/test_metrics"
echo "All native bridge regressions passed."
