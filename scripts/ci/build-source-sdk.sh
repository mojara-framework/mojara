#!/usr/bin/env bash
# Compile platform-native libraries and the entire Mojo application framework.
# No x86-64 compiled Mojara code from the published SDK is reused.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SDK="$ROOT/build/full-integration/sdk"
SRC="$SDK/lib/mojo"
OUT="$SDK/lib"
CC="${CC:-gcc}"
CXX="${CXX:-g++}"
mkdir -p "$OUT" "$SDK/bin"
test -d "$SRC/flare" || { echo 'Bootstrap source dependencies first' >&2; exit 2; }
test -n "${CONDA_PREFIX:-}" || { echo 'Run inside pixi run (CONDA_PREFIX required)' >&2; exit 2; }
echo "Architecture: $(uname -sm), SDK: $SDK, Mojo: $(mojo --version | head -1)"
declare -a SO=(-O2 -fPIC -shared -pthread)
NATIVE="$ROOT/source/native"
"$CC" "${SO[@]}" "$NATIVE/web.c" "$NATIVE/multi_upload.c" -o "$OUT/libmojara_web.so"
"$CC" "${SO[@]}" "$NATIVE/metrics.c" -o "$OUT/libmojara_metrics.so"
"$CC" "${SO[@]}" "$NATIVE/network_read_pool.c" -ldl -o "$OUT/libmojara_networkpool.so"
"$CC" "${SO[@]}" "$NATIVE/sqlite_read_pool.c" -lsqlite3 -o "$OUT/libmojara_sqlitepool.so"
"$CC" "${SO[@]}" "$NATIVE/mysql_bridge.c" $(pkg-config --cflags libmariadb) $(pkg-config --libs libmariadb) -o "$OUT/libmojara_mysql.so"
"$CC" "${SO[@]}" "$NATIVE/async_db_bridge.c" $(pkg-config --cflags libpq libmariadb sqlite3) -L"$OUT" -lmojara_mysql -lsqlite3 -lpq -Wl,-rpath,'$ORIGIN' -o "$OUT/libmojara_asyncdb.so"
FFI="$SRC/flare/http/ffi"
TLS="$SRC/flare/tls/ffi"
JSON="$SRC/json/cpu/simdjson_ffi"
"$CC" "${SO[@]}" "$FFI/fs_wrapper.c" -o "$OUT/libflare_fs.so"
"$CC" "${SO[@]}" "$FFI/zlib_wrapper.c" -lz -ldeflate -o "$OUT/libflare_zlib.so"
"$CC" "${SO[@]}" "$FFI/brotli_wrapper.c" -lbrotlienc -lbrotlidec -lbrotlicommon -o "$OUT/libflare_brotli.so"
"$CXX" -std=c++17 "${SO[@]}" "$TLS/openssl_wrapper.cpp" -lssl -lcrypto -o "$OUT/libflare_tls.so"
"$CXX" -std=c++17 "${SO[@]}" -I"$CONDA_PREFIX/include" "$JSON/simdjson_wrapper.cpp" -L"$CONDA_PREFIX/lib" -lsimdjson -Wl,-rpath,"$CONDA_PREFIX/lib" -o "$OUT/libsimdjson_wrapper.so"
echo "Building native Mojara CLI for $(uname -m)"
bash "$ROOT/scripts/build-cli.sh"
cp "$ROOT/build/bin/mojara" "$SDK/bin/mojara"
echo 'Compiling Mojara framework from the first-party source tree'
mojo precompile -I "$SRC" "$ROOT/source/mojara" -o "$SRC/mojara.mojoc"
test -s "$SRC/mojara.mojoc"
echo 'Native source build complete.'
