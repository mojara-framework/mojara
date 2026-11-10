#!/usr/bin/env bash
# Compile transaction-pool source independently and test ABI, leases and lifecycle.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
: "${CONDA_PREFIX:?Use Pixi/Conda to resolve native SQL dependencies}"
CC="${CC:-cc}"
export PKG_CONFIG_LIBDIR="$CONDA_PREFIX/lib/pkgconfig:$CONDA_PREFIX/share/pkgconfig:$CONDA_PREFIX/lib/mariadb/pkgconfig"
for pkg in libpq libmariadb; do
  pkg-config --exists "$pkg" || { echo "Missing $pkg from Conda" >&2; exit 2; }
done

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
src="$ROOT/source/native/txpool"
cflags=( -O2 -Wall -Wextra -pthread -DMJDB_INTERNAL_TEST_BACKEND -I"$src" )
read -r -a includes <<<"$(pkg-config --cflags libpq libmariadb)"
read -r -a libs <<<"$(pkg-config --libs libpq libmariadb)"
for test in test_txpool test_txpool_threads; do
  "$CC" "${cflags[@]}" "${includes[@]}" "$src/txpool.c" \
    "$ROOT/tests/native/$test.c" -o "$work/$test" \
    -L"$CONDA_PREFIX/lib" -L"$CONDA_PREFIX/lib/mariadb" \
    "${libs[@]}"
  "$work/$test"
done
echo "PASS: native transaction-pool lease, thread ownership, rollback and error-path tests"
