#!/usr/bin/env bash
# Install the Mojara native SDK and a portable Pixi-global CLI launcher.
set -Eeuo pipefail
mkdir -p "$PREFIX/opt/mojara" "$PREFIX/bin"
cp -R "$SRC_DIR/mojara/." "$PREFIX/opt/mojara/"
cat > "$PREFIX/bin/mojara" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

# BSD readlink has no -f option. Resolve the Pixi-global symlink in a
# bounded loop on macOS, without needing Python or GNU coreutils at runtime.
MOJARA_SCRIPT="${BASH_SOURCE[0]}"
for ((i = 0; i < 16; ++i)); do
  [[ -L "$MOJARA_SCRIPT" ]] || break
  link="$(readlink "$MOJARA_SCRIPT")"
  if [[ "$link" == /* ]]; then
    MOJARA_SCRIPT="$link"
  else
    MOJARA_SCRIPT="$(dirname "$MOJARA_SCRIPT")/$link"
  fi
done
[[ ! -L "$MOJARA_SCRIPT" ]] || { echo "Mojara CLI symlink resolution failed" >&2; exit 2; }
MOJARA_PREFIX="$(cd "$(dirname "$MOJARA_SCRIPT")/.." && pwd -P)"
export MOJARA_HOME="$MOJARA_PREFIX/opt/mojara"
export PATH="$MOJARA_PREFIX/bin:$PATH"
exec "$MOJARA_HOME/bin/mojara" "$@"
EOF
chmod 755 "$PREFIX/bin/mojara"
"$PREFIX/opt/mojara/bin/mojara" version
