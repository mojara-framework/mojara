#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SDK="$ROOT/build/full-integration/sdk"
export MOJARA_HOME="$SDK"
export LD_LIBRARY_PATH="$SDK/lib:${CONDA_PREFIX:-}/lib:${CONDA_PREFIX:-}/lib/mariadb:${LD_LIBRARY_PATH:-}"
: "${MOJARA_CI_PG_DSN:?PostgreSQL integration DSN is required}"
: "${MOJARA_CI_MYSQL_PASSWORD:?MariaDB test password is required}"
test -s "$SDK/lib/mojo/mojara.mojoc"
mkdir -p "$ROOT/build/full-integration"
mojo build -I "$SDK/lib/mojo" "$ROOT/tests/integration/databases.mojo" \
  -o "$ROOT/build/full-integration/databases" -Xlinker=-ldl
"$ROOT/build/full-integration/databases"
echo "PASS: Real PostgreSQL and MariaDB prepared queries and transaction controls"

# Exercise the original transaction-pool native ABI with live SQL servers.
: "${CONDA_PREFIX:?Native SQL test requires the Pixi environment}"
export PKG_CONFIG_LIBDIR="$CONDA_PREFIX/lib/pkgconfig:$CONDA_PREFIX/share/pkgconfig:$CONDA_PREFIX/lib/mariadb/pkgconfig"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export MOJARA_TEST_POSTGRES_DSN="$MOJARA_CI_PG_DSN"
export MOJARA_MYSQL_HOST="${MOJARA_CI_MYSQL_HOST:-127.0.0.1}"
export MOJARA_MYSQL_USER="mojara"
export MOJARA_MYSQL_PASSWORD="$MOJARA_CI_MYSQL_PASSWORD"
export MOJARA_MYSQL_DATABASE="mojara"
for unit in live_txpool_pg live_txpool_mysql; do
  "${CC:-cc}" -O2 -Wall -Wextra -I"$ROOT/source/native/txpool" \
    "$ROOT/tests/native/$unit.c" -L"$SDK/lib" -lmojara_txpool_ext \
    -Wl,-rpath,"$SDK/lib" -o "$work/$unit"
  "$work/$unit"
done
echo "PASS: source-built transaction pool live PostgreSQL/MariaDB multirow and rollback"
