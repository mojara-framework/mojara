#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p "$PREFIX/opt/mojara" "$PREFIX/bin"
cp -a "$SRC_DIR/mojara/." "$PREFIX/opt/mojara/"
cat > "$PREFIX/bin/mojara" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT="$(readlink -f -- "${BASH_SOURCE[0]}")"
PREFIX="$(cd "$(dirname "$SCRIPT")/.." && pwd -P)"
export MOJARA_HOME="$PREFIX/opt/mojara"
export PATH="$PREFIX/bin:$PATH"
exec "$MOJARA_HOME/bin/mojara" "$@"
EOF
chmod 755 "$PREFIX/bin/mojara"
"$PREFIX/bin/mojara" version
