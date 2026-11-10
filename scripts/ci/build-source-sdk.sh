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
# pkg-config must never select the GitHub runner's system development headers.
export PKG_CONFIG_LIBDIR="$CONDA_PREFIX/lib/pkgconfig:$CONDA_PREFIX/share/pkgconfig:$CONDA_PREFIX/lib/mariadb/pkgconfig"
for dependency in libpq libmariadb sqlite3; do
  pkg-config --exists "$dependency" || { echo "Missing Conda pkg-config file: $dependency" >&2; exit 2; }
  declared_libdir="$(pkg-config --variable=libdir "$dependency")"
  [[ "$declared_libdir" == "$CONDA_PREFIX/"* ]] || {
    echo "System library selected instead of Conda: $dependency -> $declared_libdir" >&2
    exit 2
  }
  echo "Native dependency: $dependency ($declared_libdir)"
done
declare -a SO=(-O2 -fPIC -shared -pthread "-I$CONDA_PREFIX/include")
declare -a NATIVE_LIBPATH=("-L$CONDA_PREFIX/lib" "-L$CONDA_PREFIX/lib/mariadb")
NATIVE="$ROOT/source/native"
"$CC" "${SO[@]}" "$NATIVE/web.c" "$NATIVE/multi_upload.c" -o "$OUT/libmojara_web.so"
"$CC" "${SO[@]}" "$NATIVE/metrics.c" -o "$OUT/libmojara_metrics.so"
"$CC" "${SO[@]}" "$NATIVE/network_read_pool.c" -ldl -o "$OUT/libmojara_networkpool.so"
"$CC" "${SO[@]}" "$NATIVE/sqlite_read_pool.c" "${NATIVE_LIBPATH[@]}" -lsqlite3 -o "$OUT/libmojara_sqlitepool.so"
"$CC" "${SO[@]}" "$NATIVE/mysql_bridge.c" $(pkg-config --cflags libmariadb) "${NATIVE_LIBPATH[@]}" $(pkg-config --libs libmariadb) -o "$OUT/libmojara_mysql.so"
"$CC" "${SO[@]}" "$NATIVE/async_db_bridge.c" $(pkg-config --cflags libpq libmariadb sqlite3) -L"$OUT" "${NATIVE_LIBPATH[@]}" -lmojara_mysql -lsqlite3 -lpq -Wl,-rpath,'$ORIGIN' -o "$OUT/libmojara_asyncdb.so"
TXPOOL="$NATIVE/txpool"
"$CC" "${SO[@]}" "$TXPOOL/txpool.c" $(pkg-config --cflags libpq libmariadb) "${NATIVE_LIBPATH[@]}" $(pkg-config --libs libpq libmariadb) -Wl,-rpath,'$ORIGIN' -o "$OUT/libmojara_txpool_ext.so"
"$CC" "${SO[@]}" -I"$TXPOOL" "$TXPOOL/txpool_mojo_bridge.c" -L"$OUT" -lmojara_txpool_ext -Wl,-rpath,'$ORIGIN' -o "$OUT/libmojara_txpool_mojo.so"
nm -D "$OUT/libmojara_txpool_mojo.so" | grep -q ' mjx_postgres
FFI="$SRC/flare/http/ffi"
TLS="$SRC/flare/tls/ffi"
JSON="$SRC/json/cpu/simdjson_ffi"
"$CC" "${SO[@]}" "$FFI/fs_wrapper.c" -o "$OUT/libflare_fs.so"
"$CC" "${SO[@]}" "$FFI/zlib_wrapper.c" "${NATIVE_LIBPATH[@]}" -lz -ldeflate -o "$OUT/libflare_zlib.so"
"$CC" "${SO[@]}" "$FFI/brotli_wrapper.c" "${NATIVE_LIBPATH[@]}" -lbrotlienc -lbrotlidec -lbrotlicommon -o "$OUT/libflare_brotli.so"
"$CXX" -std=c++17 "${SO[@]}" "$TLS/openssl_wrapper.cpp" "${NATIVE_LIBPATH[@]}" -lssl -lcrypto -o "$OUT/libflare_tls.so"
"$CXX" -std=c++17 "${SO[@]}" -I"$CONDA_PREFIX/include" "$JSON/simdjson_wrapper.cpp" "${NATIVE_LIBPATH[@]}" -lsimdjson -Wl,-rpath,'$ORIGIN' -o "$OUT/libsimdjson_wrapper.so"
echo "Building native Mojara CLI for $(uname -m)"
bash "$ROOT/scripts/build-cli.sh"
cp "$ROOT/build/bin/mojara" "$SDK/bin/mojara"
echo 'Compiling Mojara framework from the first-party source tree'
mojo precompile -I "$SRC" "$ROOT/source/mojara" -o "$SRC/mojara.mojoc"
test -s "$SRC/mojara.mojoc"
bash "$ROOT/scripts/ci/test-txpool-native.sh"
echo "Native source build complete."

FFI="$SRC/flare/http/ffi"
TLS="$SRC/flare/tls/ffi"
JSON="$SRC/json/cpu/simdjson_ffi"
"$CC" "${SO[@]}" "$FFI/fs_wrapper.c" -o "$OUT/libflare_fs.so"
"$CC" "${SO[@]}" "$FFI/zlib_wrapper.c" "${NATIVE_LIBPATH[@]}" -lz -ldeflate -o "$OUT/libflare_zlib.so"
"$CC" "${SO[@]}" "$FFI/brotli_wrapper.c" "${NATIVE_LIBPATH[@]}" -lbrotlienc -lbrotlidec -lbrotlicommon -o "$OUT/libflare_brotli.so"
"$CXX" -std=c++17 "${SO[@]}" "$TLS/openssl_wrapper.cpp" "${NATIVE_LIBPATH[@]}" -lssl -lcrypto -o "$OUT/libflare_tls.so"
"$CXX" -std=c++17 "${SO[@]}" -I"$CONDA_PREFIX/include" "$JSON/simdjson_wrapper.cpp" "${NATIVE_LIBPATH[@]}" -lsimdjson -Wl,-rpath,'$ORIGIN' -o "$OUT/libsimdjson_wrapper.so"
echo "Building native Mojara CLI for $(uname -m)"
bash "$ROOT/scripts/build-cli.sh"
cp "$ROOT/build/bin/mojara" "$SDK/bin/mojara"
echo 'Compiling Mojara framework from the first-party source tree'
mojo precompile -I "$SRC" "$ROOT/source/mojara" -o "$SRC/mojara.mojoc"
test -s "$SRC/mojara.mojoc"
echo 'Native source build complete.'
