#!/usr/bin/env bash
# Compile the first-party Mojo framework and native C bridges as Apple Silicon
# Mach-O libraries. Never reuse the Linux binary SDK from pinned source.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ "$(uname -s)/$(uname -m)" == "Darwin/arm64" ]] || {
  echo "macOS Apple Silicon required" >&2; exit 2;
}
: "${CONDA_PREFIX:?Run within Pixi}"
SDK="$ROOT/build/full-integration/sdk"
SRC="$SDK/lib/mojo"
OUT="$SDK/lib"
mkdir -p "$OUT" "$SDK/bin"
test -d "$SRC/flare"
export PKG_CONFIG_LIBDIR="$CONDA_PREFIX/lib/pkgconfig:$CONDA_PREFIX/share/pkgconfig:$CONDA_PREFIX/lib/mariadb/pkgconfig"
for dep in libpq libmariadb sqlite3; do
  pkg-config --exists "$dep" || { echo "Missing Conda native package: $dep" >&2; exit 2; }
  echo "$dep ($(pkg-config --variable=libdir "$dep"))"
done
CC="${CC:-clang}"
CXX="${CXX:-clang++}"
COMMON=(-O2 -fPIC -dynamiclib -pthread "-I$CONDA_PREFIX/include" "-L$CONDA_PREFIX/lib" "-Wl,-rpath,@loader_path" "-Wl,-rpath,$CONDA_PREFIX/lib")
NATIVE="$ROOT/source/native"
FFI="$SRC/flare/http/ffi"
TLS="$SRC/flare/tls/ffi"
JSON="$SRC/json/cpu/simdjson_ffi"
build_c() {
  local name="$1"; shift
  "$CC" "${COMMON[@]}" "$@" "-Wl,-install_name,@rpath/$name" -o "$OUT/$name"
}
build_cpp() {
  local name="$1"; shift
  "$CXX" -std=c++17 "${COMMON[@]}" "$@" "-Wl,-install_name,@rpath/$name" -o "$OUT/$name"
}
build_c libmojara_web.dylib "$NATIVE/web.c" "$NATIVE/multi_upload.c"
build_c libmojara_metrics.dylib "$NATIVE/metrics.c"
build_c libmojara_networkpool.dylib "$NATIVE/network_read_pool.c"
build_c libmojara_sqlitepool.dylib "$NATIVE/sqlite_read_pool.c" -lsqlite3
build_c libmojara_mysql.dylib "$NATIVE/mysql_bridge.c" $(pkg-config --cflags --libs libmariadb)
build_c libmojara_asyncdb.dylib "$NATIVE/async_db_bridge.c" $(pkg-config --cflags libpq libmariadb sqlite3) -L"$OUT" -lmojara_mysql -lsqlite3 -lpq
build_c libflare_fs.dylib "$FFI/fs_wrapper.c"
build_c libflare_zlib.dylib "$FFI/zlib_wrapper.c" -lz -ldeflate
build_c libflare_brotli.dylib "$FFI/brotli_wrapper.c" -lbrotlienc -lbrotlidec -lbrotlicommon
build_cpp libflare_tls.dylib "$TLS/openssl_wrapper.cpp" -lssl -lcrypto
build_cpp libsimdjson_wrapper.dylib "$JSON/simdjson_wrapper.cpp" -lsimdjson

# The recovered upstream Mojo source predates Mach-O bridge names. Patch only
# the build's working copy, leaving the pinned upstream archive unchanged.
python3 - "$SRC" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
changed = 0
for module in ("flare", "json"):
    for source in (root / module).rglob("*.mojo"):
        content = source.read_text()
        # Match the ELF library extension, not identifiers such as ".socket"
        # or ".sort_keys". Versioned library names are handled separately.
        patched = re.sub(r"\\.so(?![A-Za-z0-9_.])", ".dylib", content)
        if patched != content:
            source.write_text(patched)
            changed += 1
        if "dylibcket" in patched or "dylibrt_keys" in patched:
            raise SystemExit(f"Invalid macOS FFI source patch: {source}")
print("Adjusted native-library suffixes in macOS upstream modules:", changed)

# Flare's optional Linux-only worker balancing uses eventfd_write, which
# Darwin does not export. This feature is already disabled on non-Linux
# targets; compile its wake helper out of the macOS working source as well.
balance = root / "flare" / "runtime" / "_balance.mojo"
content = balance.read_text()
old_wake = '''    if fd <= 0:
        return
    _ = external_call["eventfd_write", c_int](c_int(fd), UInt64(1))'''
new_wake = '''    comptime if CompilationTarget.is_linux():
        if fd <= 0:
            return
        _ = external_call["eventfd_write", c_int](c_int(fd), UInt64(1))'''
if old_wake not in content:
    raise SystemExit("Expected Flare Linux-only eventfd wake function not found")
balance.write_text(content.replace(old_wake, new_wake, 1))
print("Disabled unavailable Linux eventfd symbol on macOS")
PY

export MOJARA_HOME="$SDK"
export PATH="$CONDA_PREFIX/bin:$PATH"
export DYLD_LIBRARY_PATH="$OUT:$CONDA_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
bash "$ROOT/scripts/build-cli.sh"
cp "$ROOT/build/bin/mojara" "$SDK/bin/mojara"
mojo precompile -I "$SRC" "$ROOT/source/mojara" -o "$SRC/mojara.mojoc"
test -s "$SRC/mojara.mojoc"
"$SDK/bin/mojara" doctor
echo "PASS: Apple Silicon Mojara native SDK and CLI"
