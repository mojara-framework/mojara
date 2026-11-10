#!/usr/bin/env bash
# Publish the initial Mojara release to the hosted Conda channel.
set -Eeuo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "Usage: $0 /absolute/path/to/conda" >&2
  exit 2
fi

CHANNEL="$1"
INDEXER="${MOJARA_CHANNEL_INDEXER:-rattler-index}"
RELEASE="https://github.com/mojara-framework/mojara/releases/download/v1.2.9"
command -v "$INDEXER" >/dev/null || { echo "Install rattler-index before publishing." >&2; exit 2; }
command -v curl >/dev/null || exit 2
command -v flock >/dev/null || exit 2
command -v zstd >/dev/null || exit 2
mkdir -p "$CHANNEL/linux-64" "$CHANNEL/linux-aarch64" "$CHANNEL/osx-arm64" "$CHANNEL/noarch"
CHANNEL="$(cd "$CHANNEL" && pwd -P)"
exec 9>"$CHANNEL/.mojara-publish.lock"
flock -x 9

TEMP="$(mktemp -d)"
trap 'rm -rf -- "$TEMP"' EXIT
curl -fsSL --retry 3 "$RELEASE/SHA256SUMS" -o "$TEMP/SHA256SUMS"
curl -fsSL --retry 3 "$RELEASE/SHA256SUMS-osx-arm64" -o "$TEMP/SHA256SUMS-osx-arm64"
# The build hash is determined by each native architecture's qualified
# compiler and linker output. Read filenames from the release checksums rather
# than hardcoding hashes that change for every new build.
declare -A PACKAGES
mapfile -t NAMES < <(awk '{print $2}' "$TEMP/SHA256SUMS" "$TEMP/SHA256SUMS-osx-arm64")
test "${#NAMES[@]}" -eq 3 || { echo "Release must contain exactly three packages" >&2; exit 1; }
for name in "${NAMES[@]}"; do
  [[ "$name" =~ ^mojara-1\.2\.9-[[:alnum:]_]+\.conda$ ]] || {
    echo "Unrecognized package name: $name" >&2; exit 1;
  }
  curl -fsSL --retry 3 "$RELEASE/$name" -o "$TEMP/$name"
done
(cd "$TEMP" && sha256sum -c SHA256SUMS && sha256sum -c SHA256SUMS-osx-arm64)

# Inspect the package's own Conda metadata to determine its target platform.
python3 - "$TEMP" <<'PYTHON'
import io, json, pathlib, subprocess, sys, tarfile, zipfile
root=pathlib.Path(sys.argv[1])
names=[x for x in root.glob('*.conda')]
found={}
for pkg in names:
    with zipfile.ZipFile(pkg) as zf:
        packed=[n for n in zf.namelist() if n.startswith('info-') and n.endswith('.tar.zst')]
        assert len(packed)==1, (pkg,packed)
        data=subprocess.run(['zstd','-dc'],input=zf.read(packed[0]),capture_output=True,check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(data)) as tf:
        meta=json.load(tf.extractfile('info/index.json'))
    assert meta['name']=='mojara' and meta['version']=='1.2.9', (pkg,meta)
    arch=meta['subdir']
    assert arch in ('linux-64','linux-aarch64','osx-arm64') and arch not in found, (pkg,arch)
    found[arch]=pkg.name
assert len(found)==3, found
(root/'package-map.json').write_text(json.dumps(found))
print('Validated three native Conda architectures:',found)
PYTHON
for arch in linux-64 linux-aarch64 osx-arm64; do
  PACKAGES[$arch]="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$TEMP/package-map.json" "$arch")"
done

for arch in linux-64 linux-aarch64 osx-arm64; do
  name="${PACKAGES[$arch]}"
  dest="$CHANNEL/$arch/$name"
  if [[ -e "$dest" ]]; then
    cmp -s "$TEMP/$name" "$dest" || { echo "Existing package differs: $dest" >&2; exit 1; }
  else
    pending="$(mktemp "$CHANNEL/$arch/.mojara-XXXXXXXX")"
    cp "$TEMP/$name" "$pending"
    chmod 0644 "$pending"
    mv -n "$pending" "$dest"
    test ! -e "$pending" || { rm -f "$pending"; exit 1; }
  fi
done
"$INDEXER" fs "$CHANNEL"
python3 - "$CHANNEL" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
for arch in ('linux-64','linux-aarch64','osx-arm64'):
    records=json.loads((root/arch/'repodata.json').read_text()).get('packages.conda',{})
    assert any(x.get('name')=='mojara' and x.get('version')=='1.2.9' for x in records.values())
    print('PASS:',arch,'Mojara 1.2.9 indexed')
PY
