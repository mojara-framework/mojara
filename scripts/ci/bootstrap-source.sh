#!/usr/bin/env bash
# Recover Mojo dependencies from independently pinned upstream Git revisions.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
WORK="$ROOT/build/full-integration"
SDK="$WORK/sdk"
SRC="$SDK/lib/mojo"
LOCK="$ROOT/source/upstream/UPSTREAM.lock"
MANIFEST="$ROOT/source/upstream/source-sha256.txt"
PATCH="$ROOT/source/upstream/compat.patch"
CACHE="$WORK/upstream-cache"
mkdir -p "$SRC" "$SDK/bin" "$SDK/lib" "$CACHE"

python3 - "$LOCK" "$MANIFEST" "$CACHE" "$SRC" "$SDK" <<'PY'
import hashlib
import pathlib
import re
import shutil
import sys
import tarfile
import urllib.request

lockfile, manifestfile, cache_dir, src_dir, sdk_dir = map(pathlib.Path, sys.argv[1:])
modules = ("flare", "json", "morph", "sqlite")
pins = {}
for line in lockfile.read_text().splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    fields = line.split()
    if len(fields) != 3:
        raise SystemExit("Invalid upstream pin declaration")
    module, commit, digest = fields
    if module not in modules or module in pins:
        raise SystemExit("Unexpected or duplicate upstream module pin")
    if not re.fullmatch(r"[a-f0-9]{40}", commit) or not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise SystemExit("Invalid upstream commit or archive digest")
    pins[module] = (commit, digest)
if set(pins) != set(modules):
    raise SystemExit("Missing required independently pinned upstream module")

expected = {}
for line in manifestfile.read_text().splitlines():
    digest, sep, filename = line.partition("  ")
    path = pathlib.PurePosixPath(filename)
    if not sep or not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise SystemExit("Invalid source checksum manifest")
    if path.is_absolute() or ".." in path.parts or len(path.parts) < 2:
        raise SystemExit("Unsafe source path in manifest")
    if path.parts[0] not in modules or filename in expected:
        raise SystemExit("Unexpected or duplicate source file")
    expected[filename] = digest

for module in modules:
    shutil.rmtree(src_dir / module, ignore_errors=True)

for module in modules:
    commit, digest = pins[module]
    archive_path = cache_dir / f"{module}-{commit}.tar.gz"
    if not archive_path.is_file():
        url = f"https://codeload.github.com/ehsanmok/{module}/tar.gz/{commit}"
        request = urllib.request.Request(url, headers={"User-Agent": "mojara-source-bootstrap"})
        with urllib.request.urlopen(request, timeout=90) as response:
            with archive_path.with_suffix(".part").open("wb") as output:
                shutil.copyfileobj(response, output)
        archive_path.with_suffix(".part").replace(archive_path)
    actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    if actual != digest:
        raise SystemExit(f"Upstream {module} archive SHA256 mismatch")

    with tarfile.open(archive_path, "r:gz") as archive:
        prefix = f"{module}-{commit}/"
        for filename in sorted(expected):
            if not filename.startswith(module + "/"):
                continue
            item = archive.getmember(prefix + filename)
            if not item.isfile():
                raise SystemExit(f"Non-regular upstream source file: {filename}")
            contents = archive.extractfile(item)
            if contents is None:
                raise SystemExit(f"Unreadable upstream source file: {filename}")
            destination = src_dir / filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(contents.read())

        item = archive.getmember(prefix + "LICENSE")
        if not item.isfile():
            raise SystemExit(f"Missing upstream {module} license")
        licenses = sdk_dir / "share/doc/mojara/licenses"
        licenses.mkdir(parents=True, exist_ok=True)
        (licenses / f"UPSTREAM-{module.upper()}-LICENSE.txt").write_bytes(archive.extractfile(item).read())
    print(f"Verified independent upstream {module} at {commit[:12]}")
PY

# Keep Mojara's explicitly tracked API/ABI compatibility changes; no source
# or compiled native binaries are read from any previous Mojara package.
patch -p1 -t -d "$SRC" < "$PATCH"

python3 - "$MANIFEST" "$SRC" <<'PY'
import hashlib
import pathlib
import sys

manifest, root = map(pathlib.Path, sys.argv[1:])
expected = {}
for line in manifest.read_text().splitlines():
    digest, name = line.split("  ", 1)
    expected[name] = digest

actual = {}
for module in ("flare", "json", "morph", "sqlite"):
    for path in (root / module).rglob("*"):
        if path.is_file():
            actual[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    changed = sorted(path for path in set(actual) & set(expected) if actual[path] != expected[path])
    raise SystemExit(f"Source tree verification failed: missing={missing[:5]} extra={extra[:5]} changed={changed[:5]}")
print(f"PASS: {len(expected)} independent upstream source files match pinned compatibility inventory")
PY

test ! -e "$SRC/mojara.mojoc"
echo "Native framework, CLI and C bridges will be built from first-party source."
