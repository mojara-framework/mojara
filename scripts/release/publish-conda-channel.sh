#!/usr/bin/env bash
# Publish the initial Mojara release to the hosted Conda channel.
set -Eeuo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "Usage: $0 /absolute/path/to/conda" >&2
  exit 2
fi

CHANNEL="$1"
INDEXER="${MOJARA_CHANNEL_INDEXER:-rattler-index}"
RELEASE="https://github.com/mojara-framework/mojara/releases/download/v1.2.8"
command -v "$INDEXER" >/dev/null || { echo "Install rattler-index before publishing." >&2; exit 2; }
command -v curl >/dev/null || exit 2
command -v flock >/dev/null || exit 2
mkdir -p "$CHANNEL/linux-64" "$CHANNEL/linux-aarch64" "$CHANNEL/osx-arm64" "$CHANNEL/noarch"
CHANNEL="$(cd "$CHANNEL" && pwd -P)"
exec 9>"$CHANNEL/.mojara-publish.lock"
flock -x 9

TEMP="$(mktemp -d)"
trap 'rm -rf -- "$TEMP"' EXIT
curl -fsSL --retry 3 "$RELEASE/SHA256SUMS" -o "$TEMP/SHA256SUMS"
curl -fsSL --retry 3 "$RELEASE/SHA256SUMS-osx-arm64" -o "$TEMP/SHA256SUMS-osx-arm64"
declare -A PACKAGES=(
  [linux-64]=mojara-1.2.8-hb0f4dca_0.conda
  [linux-aarch64]=mojara-1.2.8-he8cfe8b_0.conda
  [osx-arm64]=mojara-1.2.8-h60d57d3_0.conda
)
for arch in linux-64 linux-aarch64 osx-arm64; do
  name="${PACKAGES[$arch]}"
  curl -fsSL --retry 3 "$RELEASE/$name" -o "$TEMP/$name"
done
(cd "$TEMP" && sha256sum -c SHA256SUMS && sha256sum -c SHA256SUMS-osx-arm64)

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
    assert any(x.get('name')=='mojara' and x.get('version')=='1.2.8' for x in records.values())
    print('PASS:',arch,'Mojara 1.2.8 indexed')
PY
