#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p "$PREFIX/opt/mojara" "$PREFIX/bin"
cp -a "$SRC_DIR/mojara/." "$PREFIX/opt/mojara/"

# Entry point uses the native Mojo executable; this tiny shell shim only
# resolves the Conda/Pixi installation prefix. No Python runtime is involved.
cat > "$PREFIX/bin/mojara" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
# Pixi global exposes this script using a symlink. Resolve the installed
# script first so the prefix is the real package environment, not ~/.pixi.
MOJARA_SCRIPT="$(readlink -f -- "${BASH_SOURCE[0]}")"
MOJARA_PREFIX="$(cd "$(dirname "$MOJARA_SCRIPT")/.." && pwd -P)"
export MOJARA_HOME="$MOJARA_PREFIX/opt/mojara"
# Make the bundled Mojo compiler and watchexec accessible without a pixi.toml.
export PATH="$MOJARA_PREFIX/bin:$PATH"
exec "$MOJARA_HOME/bin/mojara" "$@"
EOF
chmod 755 "$PREFIX/bin/mojara"
"$PREFIX/opt/mojara/bin/mojara" version
