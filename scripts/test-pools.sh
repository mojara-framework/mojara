#!/usr/bin/env bash
# Deterministic native pool tests on the actual GitHub runner CPU.
# PostgreSQL/MySQL shared libraries below are LOCAL mocks only;
# live database integration is covered by full-linux-integration.yml.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD="$ROOT/build/pool-regressions"
SRC="$ROOT/source/native"
T="$ROOT/tests/native"
CC="${CC:-cc}"
mkdir -p "$BUILD"
FLAGS=(-std=gnu11 -O2 -pthread)
echo "Pool regression platform: $(uname -srm)"
"$CC" "${FLAGS[@]}" -fPIC -shared -DMOCK_PG "$T/test_network_pool_mock.c" -o "$BUILD/libpq.so.5"
"$CC" "${FLAGS[@]}" -fPIC -shared -DMOCK_MY "$T/test_network_pool_mock.c" -o "$BUILD/libmojara_mysql.so"
"$CC" "${FLAGS[@]}" -DMJ_NP_TESTING "$SRC/network_read_pool.c" "$T/test_network_pool.c" -ldl -o "$BUILD/test_network_pool"
(
    cd "$BUILD"
    LD_LIBRARY_PATH="$BUILD:${LD_LIBRARY_PATH:-}" timeout 50s ./test_network_pool
)
"$CC" "${FLAGS[@]}" -DMJ_SP_TESTING "$SRC/sqlite_read_pool.c" "$T/test_sqlite_pool_shutdown.c" -lsqlite3 -o "$BUILD/test_sqlite_pool_shutdown"
timeout 50s "$BUILD/test_sqlite_pool_shutdown"
"$CC" "${FLAGS[@]}" "$SRC/sqlite_read_pool.c" "$T/test_sqlite_read_pool.c" -lsqlite3 -o "$BUILD/test_sqlite_read_pool"
timeout 90s "$BUILD/test_sqlite_read_pool"
echo "PASS: Native pool reuse, SQL guardrails, bounded leases, concurrency and graceful shutdown"
