#!/usr/bin/env bash
# Audit the native ELF binaries and declared runtime dependencies in a Conda archive.
set -Eeuo pipefail

if [[ $# -ne 1 || ! -s "$1" || "$1" != *.conda ]]; then
  echo "Usage: audit-release-abi.sh PATH/TO/MOJARA.conda" >&2
  exit 2
fi
for tool in unzip tar zstd readelf python3; do
  command -v "$tool" >/dev/null || { echo "Missing ABI audit tool: $tool" >&2; exit 2; }
done

PACKAGE="$(realpath "$1")"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
cd "$WORK"
pkg_archive="$(unzip -Z1 "$PACKAGE" | grep -E '^pkg-[^/]+\.tar\.zst$' | head -1)"
info_archive="$(unzip -Z1 "$PACKAGE" | grep -E '^info-[^/]+\.tar\.zst$' | head -1)"
if [[ -z "$pkg_archive" || -z "$info_archive" ]]; then
  echo "Malformed Conda package: missing pkg/info archives" >&2
  exit 1
fi
unzip -oq "$PACKAGE" "$pkg_archive" "$info_archive"
tar -I zstd -xf "$pkg_archive"
tar -I zstd -xf "$info_archive"

python3 - "$WORK" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
metadata = json.loads((root / "info/index.json").read_text())
subdir = metadata.get("subdir")
machines = {
    "linux-64": "Advanced Micro Devices X86-64",
    "linux-aarch64": "AArch64",
}
if subdir not in machines:
    raise SystemExit(f"Unsupported Linux native package subdir: {subdir!r}")

dependencies = {item.split()[0] for item in metadata.get("depends", [])}
# Ordinary glibc and the ELF interpreter come from Linux; other external
# shared libraries must have a provider in the Conda runtime metadata.
providers = {
    "libKGENCompilerRTShared.so": ("mojo",),
    "libmariadb.so.3": ("mariadb-connector-c",),
    "libpq.so.5": ("libpq",),
    "libsqlite3.so.0": ("sqlite", "libsqlite"),
    "libssl.so.3": ("openssl",),
    "libcrypto.so.3": ("openssl",),
    "libz.so.1": ("zlib", "libzlib"),
    "libdeflate.so.0": ("libdeflate",),
    "libbrotlienc.so.1": ("brotli", "libbrotlienc"),
    "libbrotlidec.so.1": ("brotli", "libbrotlidec"),
    "libbrotlicommon.so.1": ("brotli", "libbrotlicommon"),
    "libsimdjson.so.33": ("simdjson",),
    "libstdc++.so.6": ("libstdcxx", "libstdcxx-ng"),
    "libgcc_s.so.1": ("libgcc", "libgcc-ng"),
}
system_sonames = {
    "libc.so.6", "ld-linux-x86-64.so.2", "ld-linux-aarch64.so.1",
}
sdk = root / "opt/mojara"
cli = sdk / "bin/mojara"
libraries = sorted((sdk / "lib").glob("*.so"))
binaries = [cli, *libraries]
if not cli.is_file() or len(libraries) < 10:
    raise SystemExit("Native CLI or first-party shared library inventory is incomplete")

bundled = {path.name for path in libraries}
failures = []
max_glibc = (0, 0)
providers_used = set()

def readelf(flag, path):
    return subprocess.check_output(
        ["readelf", flag, str(path)], text=True, stderr=subprocess.STDOUT
    )

for binary in binaries:
    label = str(binary.relative_to(root))
    with binary.open("rb") as stream:
        if stream.read(4) != b"\x7fELF":
            failures.append(f"{label}: not an ELF binary")
            continue

    header = readelf("-h", binary)
    machine = re.search(r"^\s*Machine:\s*(.+)$", header, re.MULTILINE)
    if not machine or machines[subdir] not in machine.group(1):
        actual = machine.group(1) if machine else "unknown"
        failures.append(f"{label}: wrong ELF architecture ({actual})")

    dynamic = readelf("-d", binary)
    needed = re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", dynamic)
    rpaths = re.findall(
        r"\((?:RPATH|RUNPATH)\)\s+Library (?:rpath|runpath): \[([^\]]*)\]", dynamic
    )
    if not rpaths:
        failures.append(f"{label}: no relocatable loader search path")
    for rpath in rpaths:
        for entry in rpath.split(":"):
            if not (entry == "$ORIGIN" or entry.startswith("$ORIGIN/")):
                failures.append(f"{label}: non-relocatable loader path {entry!r}")
                continue
            resolved = pathlib.Path(entry.replace("$ORIGIN", str(binary.parent), 1)).resolve()
            if not resolved.is_relative_to(root):
                failures.append(f"{label}: loader path escapes Conda prefix: {entry}")

    for soname in needed:
        if "/" in soname:
            failures.append(f"{label}: embedded library path in DT_NEEDED: {soname}")
        elif soname in bundled or soname in system_sonames:
            continue
        elif soname not in providers:
            failures.append(f"{label}: unknown external library: {soname}")
        elif not set(providers[soname]).intersection(dependencies):
            failures.append(f"{label}: undeclared runtime provider for {soname}")
        else:
            providers_used.add(soname)

    for major, minor in re.findall(r"\bGLIBC_(\d+)\.(\d+)", readelf("--version-info", binary)):
        max_glibc = max(max_glibc, (int(major), int(minor)))

# Keep the published compatibility baseline explicit. A higher GLIBC target
# requires deliberate release qualification rather than an accidental bump.
if max_glibc > (2, 34):
    failures.append(f"GLIBC ABI exceeds the 2.34 baseline: {max_glibc[0]}.{max_glibc[1]}")

if failures:
    print("FAIL: Mojara native release ABI audit", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    raise SystemExit(1)

print(
    f"PASS: {metadata['name']} {metadata['version']} {subdir}: "
    f"{len(binaries)} ELF binaries; {len(providers_used)} external SONAMEs "
    f"with declared providers; relative loader paths; GLIBC {max_glibc[0]}.{max_glibc[1]}"
)
PY
