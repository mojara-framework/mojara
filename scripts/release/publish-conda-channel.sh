#!/usr/bin/env bash
# Publish verified Mojara 1.2.6 binaries without deleting older packages.
set -Eeuo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "Usage: $0 /absolute/path/to/conda" >&2
  exit 2
fi

CHANNEL="$1"
RELEASE="https://github.com/mojara-framework/mojara/releases/download/v1.2.6"
INDEXER="${MOJARA_CHANNEL_INDEXER:-rattler-index}"
command -v curl >/dev/null || { echo "curl required" >&2; exit 2; }
command -v flock >/dev/null || { echo "flock required" >&2; exit 2; }
command -v "$INDEXER" >/dev/null || {
  echo "rattler-index is required. Install with: pixi global install rattler-index -c conda-forge" >&2
  exit 2
}
[[ -d "$CHANNEL/linux-64" ]] || {
  echo "Cannot find existing linux-64 channel: $CHANNEL" >&2; exit 2;
}
CHANNEL="$(cd "$CHANNEL" && pwd -P)"

# Prevent discarding entries from a channel whose indexed packages are
# actually on remote storage or otherwise missing from this filesystem.
python3 - "$CHANNEL" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for platform in ("linux-64", "linux-aarch64", "noarch"):
    index = root / platform / "repodata.json"
    if not index.is_file():
        continue
    data = json.loads(index.read_text())
    missing = [
        name
        for key in ("packages", "packages.conda")
        for name in data.get(key, {})
        if not (root / platform / name).is_file()
    ]
    if missing:
        raise SystemExit(
            f"Refusing incomplete {platform} channel: "
            f"index references missing package files {missing[:5]}"
        )
print("PASS: Existing channel package inventory is complete")
PY

mkdir -p "$CHANNEL/linux-aarch64" "$CHANNEL/noarch"
exec 9>"$CHANNEL/.mojara-publish.lock"
flock -x 9

TEMP="$(mktemp -d)"
trap 'rm -rf -- "$TEMP"' EXIT

curl -fSL --retry 3 --connect-timeout 15 "$RELEASE/SHA256SUMS" -o "$TEMP/SHA256SUMS"
for platform in linux-64 linux-aarch64; do
  case "$platform" in
    linux-64) name="mojara-1.2.6-hb0f4dca_0.conda" ;;
    linux-aarch64) name="mojara-1.2.6-he8cfe8b_0.conda" ;;
  esac
  curl -fSL --retry 3 --connect-timeout 15 "$RELEASE/$name" -o "$TEMP/$name"
done
(cd "$TEMP" && sha256sum -c SHA256SUMS)
echo "PASS: Both public release assets match GitHub SHA256SUMS"

for platform in linux-64 linux-aarch64; do
  case "$platform" in
    linux-64) name="mojara-1.2.6-hb0f4dca_0.conda" ;;
    linux-aarch64) name="mojara-1.2.6-he8cfe8b_0.conda" ;;
  esac
  dest="$CHANNEL/$platform/$name"
  if [[ -e "$dest" ]]; then
    cmp -s "$TEMP/$name" "$dest" || {
      echo "Existing package has different content: $dest" >&2
      exit 1
    }
    continue
  fi
  pending="$(mktemp "$CHANNEL/$platform/.mojara-upload-XXXXXXXX")"
  cp "$TEMP/$name" "$pending"
  chmod 0644 "$pending"
  mv -n "$pending" "$dest"
  if [[ -e "$pending" ]]; then
    rm -f "$pending"
    echo "Package installation conflict: $dest" >&2
    exit 1
  fi
done

"$INDEXER" fs "$CHANNEL"

python3 - "$CHANNEL" "$TEMP" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
staged = pathlib.Path(sys.argv[2])
files = {
    "linux-64": "mojara-1.2.6-hb0f4dca_0.conda",
    "linux-aarch64": "mojara-1.2.6-he8cfe8b_0.conda",
}
for platform, name in files.items():
    index = json.loads((root / platform / "repodata.json").read_text())
    record = index.get("packages.conda", {}).get(name)
    if record is None:
        raise SystemExit(f"Missing {platform} package entry in repodata.json")
    if record.get("name") != "mojara" or record.get("version") != "1.2.6":
        raise SystemExit(f"Incorrect {platform} package metadata: {record}")
    checksum = hashlib.sha256((staged / name).read_bytes()).hexdigest()
    if record.get("sha256") != checksum:
        raise SystemExit(f"Incorrect {platform} package checksum in index")
    print(f"PASS: Indexed Mojara 1.2.6 on {platform}")
print("PASS: Existing channel packages retained")
PY
