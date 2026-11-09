#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SDK="$ROOT/build/full-integration/sdk"
export MOJARA_HOME="$SDK"
export LD_LIBRARY_PATH="$SDK/lib:${CONDA_PREFIX:-}/lib:${LD_LIBRARY_PATH:-}"
: "${MOJARA_CI_PG_DSN:?PostgreSQL integration DSN is required}"
: "${MOJARA_CI_MYSQL_PASSWORD:?MariaDB test password is required}"
test -s "$SDK/lib/mojo/mojara.mojoc"
mkdir -p "$ROOT/build/full-integration"
mojo build -I "$SDK/lib/mojo" "$ROOT/tests/integration/databases.mojo" \
  -o "$ROOT/build/full-integration/databases" -Xlinker=-ldl
"$ROOT/build/full-integration/databases"
echo "PASS: Real PostgreSQL and MariaDB prepared queries and transaction controls"
