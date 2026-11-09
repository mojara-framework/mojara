#!/usr/bin/env bash
# Download SHA-256-verified Mojara SDK to recover upstream Mojo SOURCE modules.
# Never reuse SDK x86-64 native libraries or precompiled mojara.mojoc on ARM64.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$ROOT/build/full-integration"
SDK="$WORK/sdk"
PKG="$WORK/mojara-1.2.5.conda"
mkdir -p "$WORK" "$SDK/lib/mojo" "$SDK/bin" "$SDK/lib"
URL="https://mojara.kasua.ng/conda/linux-64/mojara-1.2.5-hb0f4dca_0.conda"
SHA="838bb8d3404a8f481e2ec18236a539599dd66d151ae6a758675e6b4f1b893e02"
if [ ! -f "$PKG" ]; then
  curl -fSL --retry 3 --connect-timeout 15 "$URL" -o "$PKG"
fi
if command -v sha256sum >/dev/null 2>&1; then
  echo "$SHA  $PKG" | sha256sum -c -
else
  echo "$SHA  $PKG" | shasum -a 256 -c -
fi
python3 - "$PKG" "$WORK" <<'PY'
import sys, zipfile, subprocess, pathlib, shutil
pkg=pathlib.Path(sys.argv[1])
work=pathlib.Path(sys.argv[2])
staging=work/'source-staging'
staging.mkdir(exist_ok=True)
with zipfile.ZipFile(pkg) as archive:
    filename=next(n for n in archive.namelist() if n.startswith('pkg-') and n.endswith('.tar.zst'))
    tar=work/pathlib.Path(filename).name
    if not tar.is_file(): tar.write_bytes(archive.read(filename))
with subprocess.Popen(['zstd','-dc',str(tar)],stdout=subprocess.PIPE) as decoder:
    subprocess.run(['tar','-xf','-','-C',str(staging)],stdin=decoder.stdout,check=True)
    decoder.stdout.close()
    if decoder.wait(): raise SystemExit('Failed to decompress pinned Mojo source archive')
sdk_sources=staging/'opt/mojara/lib/mojo'
target=work/'sdk/lib/mojo'
for module in ('flare','json','morph','sqlite'):
    original=sdk_sources/module
    if not original.is_dir(): raise SystemExit('Missing pinned dependency source: '+module)
    shutil.copytree(original,target/module,dirs_exist_ok=True)
print('Recovered Flare/JSON/Morph/SQLite source from pinned release.')
PY
test ! -e "$SDK/lib/mojo/mojara.mojoc"
echo "Native framework and C bridges must be rebuilt from source."
