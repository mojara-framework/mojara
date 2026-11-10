#!/usr/bin/env bash
# Install the verified Mojara 1.2.9 package directly from the official release.
set -Eeuo pipefail

VERSION="1.2.9"
RELEASE="https://github.com/mojara-framework/mojara/releases/download/v${VERSION}"
OS="$(uname -s)"
CPU="$(uname -m)"

case "${OS}:${CPU}" in
  Linux:x86_64|Linux:amd64)
    PACKAGE="mojara-1.2.9-hb0f4dca_0.conda"
    MANIFEST="SHA256SUMS"
    ;;
  Linux:aarch64|Linux:arm64)
    PACKAGE="mojara-1.2.9-he8cfe8b_0.conda"
    MANIFEST="SHA256SUMS"
    ;;
  Darwin:arm64)
    MANIFEST="SHA256SUMS-osx-arm64"
    PACKAGE=""
    ;;
  *)
    printf 'Unsupported native Mojara installer target: %s/%s\n' "$OS" "$CPU" >&2
    printf 'Windows users: run this inside WSL2 Ubuntu. Intel Macs: use Mojara Docker.\n' >&2
    exit 2
    ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
printf 'Fetching official Mojara %s release metadata...\n' "$VERSION"
if ! curl --fail --silent --show-error --location --retry 3 \
    "${RELEASE}/${MANIFEST}" -o "${TMP}/${MANIFEST}"; then
  printf 'No verified Mojara %s package is currently published for %s/%s. Existing installation was not changed.\n' \
    "$VERSION" "$OS" "$CPU" >&2
  exit 1
fi

if [[ -z "$PACKAGE" ]]; then
  PACKAGE="$(awk '$2 ~ /^mojara-1[.]2[.]9-.*[.]conda$/ { print $2 }' "${TMP}/${MANIFEST}")"
  [[ -n "$PACKAGE" && "$PACKAGE" != *$'\n'* ]] || {
    printf 'Release manifest does not identify exactly one native macOS package.\n' >&2
    exit 1
  }
fi

EXPECTED="$(awk -v name="$PACKAGE" '$2 == name { print $1 }' "${TMP}/${MANIFEST}")"
if [[ ! "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]]; then
  printf 'Release checksum is missing or invalid for %s.\n' "$PACKAGE" >&2
  exit 1
fi
curl --fail --silent --show-error --location --retry 3 \
  "${RELEASE}/${PACKAGE}" -o "${TMP}/${PACKAGE}"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "${TMP}/${PACKAGE}" | awk '{print $1}')"
else
  ACTUAL="$(shasum -a 256 "${TMP}/${PACKAGE}" | awk '{print $1}')"
fi
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  printf 'Mojara package checksum failed. Existing installation was not changed.\n' >&2
  exit 1
fi
printf 'Verified official package: %s\n' "$PACKAGE"

if ! command -v pixi >/dev/null 2>&1; then
  printf 'Installing Pixi package manager...\n'
  curl --fail --silent --show-error --location https://pixi.sh/install.sh | bash
  export PATH="$HOME/.pixi/bin:$PATH"
fi
command -v pixi >/dev/null 2>&1 || {
  printf 'Pixi was not found after setup. Existing Mojara installation was not changed.\n' >&2
  exit 1
}

# All downloads and SHA-256 verification happen BEFORE replacing an old version.
# Pixi installs Mojara and its compatible Mojo compiler, no source clone needed.
pixi global uninstall mojara >/dev/null 2>&1 || true
pixi global install --path "${TMP}/${PACKAGE}" \
  -c https://conda.modular.com/max/ -c conda-forge

export PATH="$HOME/.pixi/bin:$PATH"
mojara version
mojara doctor
printf 'Mojara %s installed.\n' "$VERSION"
