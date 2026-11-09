#!/usr/bin/env bash
# Compile and run database tests using ONLY an installed package and services.
set -Eeuo pipefail
if [[ $# -ne 1 ]]; then echo "Usage: $0 PIXI_HOME" >&2; exit 2; fi
: "${MOJARA_CI_PG_DSN:?PostgreSQL CI service required}"
: "${MOJARA_CI_MYSQL_PASSWORD:?MariaDB CI service required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SDK_BIN="$(find "$1/envs" -path '*/opt/mojara/bin/mojara' -type f -print -quit)"
test -n "$SDK_BIN"
export MOJARA_HOME="$(cd "$(dirname "$SDK_BIN")/.." && pwd -P)"
export CONDA_PREFIX="$(cd "$MOJARA_HOME/../.." && pwd -P)"
export PATH="$CONDA_PREFIX/bin:$PATH"
# The Mojo dynamic loading boundary uses LD_LIBRARY_PATH to discover the
# framework-native bridge itself; verify-installed-links.sh first verifies
# all the library dependencies without this override.
export LD_LIBRARY_PATH="$MOJARA_HOME/lib:$CONDA_PREFIX/lib:$CONDA_PREFIX/lib/mariadb"
BUILD="$ROOT/build/fresh-package-verify"
mkdir -p "$BUILD"
"$CONDA_PREFIX/bin/mojo" build -I "$MOJARA_HOME/lib/mojo" \
  "$ROOT/tests/integration/databases.mojo" \
  -o "$BUILD/installed-databases" -Xlinker=-ldl
"$BUILD/installed-databases"
echo "PASS: Installed package handles live PostgreSQL and MariaDB SQL on a clean runner"
