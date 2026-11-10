#!/usr/bin/env bash
# Safely synchronize Mojara's public GitHub installation guides to the Mojo-hosted website.
set -Eeuo pipefail
umask 027

ROOT=/srv/mojara-website-app
CACHE=/var/cache/mojara-doc-sync
BACKUPS=/srv/mojara-site-backups
GITHUB_REPO=https://github.com/mojara-framework/mojara.git
COMMIT="$(git ls-remote "$GITHUB_REPO" refs/heads/main | awk '{print $1}')"
[[ "$COMMIT" =~ ^[a-f0-9]{40}$ ]] || { echo "Cannot resolve GitHub main commit" >&2; exit 1; }
RAW="https://raw.githubusercontent.com/mojara-framework/mojara/$COMMIT"
VENV=/opt/mojara-doc-sync-venv
mkdir -p "$CACHE" "$BACKUPS"
exec 9>"/run/lock/mojara-doc-sync.lock"
flock -n 9 || exit 0

scratch=$(mktemp -d "$CACHE/check.XXXXXXXX")
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

for file in README.md docs/DOCKER.md docs/BUILD-FROM-SOURCE.md scripts/docs/sync-hosted-installation.py; do
  mkdir -p "$scratch/$(dirname "$file")"
  curl --fail --silent --show-error --location --retry 3 --max-time 35 \
    "$RAW/$file" --output "$scratch/$file"
  test -s "$scratch/$file"
done
"$VENV/bin/python" -m py_compile "$scratch/scripts/docs/sync-hosted-installation.py"

# Re-render only if the Markdown or the renderer has changed.
digest=$(
  cd "$scratch"
  sha256sum README.md docs/DOCKER.md docs/BUILD-FROM-SOURCE.md scripts/docs/sync-hosted-installation.py |
    sha256sum | cut -d' ' -f1
)
if [[ -f "$CACHE/last-applied" ]] && [[ "$(cat "$CACHE/last-applied")" == "$digest" ]]; then
  exit 0
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUPS/mojara-doc-sync-$stamp.tar.gz"
tar -C "$ROOT" -czf "$backup" content site/docs site/search.json site/sitemap.xml
tar -C /var/www/mojara-site -czf "$scratch/fallback.tar.gz" docs search.json sitemap.xml

rollback() {
  echo "Documentation sync did not qualify; restoring the previous website." >&2
  tar -C "$ROOT" -xzf "$backup"
  tar -C /var/www/mojara-site -xzf "$scratch/fallback.tar.gz"
  exit 1
}
trap rollback ERR

install -m 0644 "$scratch/scripts/docs/sync-hosted-installation.py" "$ROOT/tests/sync_installation_docs.py"
"$VENV/bin/python" "$ROOT/tests/sync_installation_docs.py"

"$VENV/bin/python" - <<'PY'
from pathlib import Path
import json
root = Path("/srv/mojara-website-app/site")
pages = {n: (root / "docs" / f"{n}.html").read_text()
         for n in ("install", "docker", "source-build", "quickstart", "releases")}
assert all(p.count('<article class="article">') == 1 for p in pages.values())
assert all("</article>" in p for p in pages.values())
assert "ghcr.io/mojara-framework/mojara:" in pages["docker"]
assert "bootstrap-source.sh" in pages["source-build"]
assert "mojara==1.2.7" in pages["install"]
index = json.loads((root / "search.json").read_text())
assert {"install", "docker", "source-build"} <= {e["slug"] for e in index}
for path in ("docker", "source-build"):
    assert f"/docs/{path}.html" in (root / "sitemap.xml").read_text()
print("PASS: new Mojara docs and navigation qualified")
PY

if ! systemctl is-active --quiet mojara-website; then
  echo "Mojara website service is not active" >&2
  false
fi
curl --fail --silent --show-error --max-time 5 \
  http://127.0.0.1:18767/api/health | grep -q '"status":"ok"'

printf '%s\n' "$digest" >"$CACHE/last-applied.tmp"
mv "$CACHE/last-applied.tmp" "$CACHE/last-applied"
trap - ERR

# Keep only the last five automatic deployment backups.
ls -1t "$BACKUPS"/mojara-doc-sync-*.tar.gz 2>/dev/null |
  tail -n +6 | xargs -r rm -f --
echo "Updated Mojara hosted installation documentation from GitHub main: $digest"
