#!/usr/bin/env bash
set -Eeuo pipefail

# Smoke-test the compiled Mojo CLI without touching existing applications.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLI="${MOJARA_CLI:-$ROOT/build/bin/mojara}"
test -x "$CLI" || { echo "Build the Mojara CLI first: $CLI" >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
cd "$WORK"

"$CLI" site new example
test -f example/content/index.md
test -f example/templates/base.html
test ! -e example/app.mojo

cd example
mkdir -p build content/blog static/img
printf 'keep dynamic build directory untouched\n' > build/app
printf '\000\377\001' > static/img/data.bin
cat > content/blog/first.md <<'EOF'
---
title: First & Second
description: A <sample> page
---

# Welcome

A **bold** word, `code` and [documentation](https://example.com).

- One
- Two

```mojo
print("<unsafe>")
```

<script>alert("unsafe")</script>
EOF
"$CLI" site build
test -f dist/.mojara-site
test -f dist/index.html
test -f dist/blog/first/index.html
test -f dist/static/style.css
cmp static/img/data.bin dist/static/img/data.bin
grep -q 'First &amp; Second' dist/blog/first/index.html
grep -q 'A &lt;sample&gt; page' dist/blog/first/index.html
grep -q '<strong>bold</strong>' dist/blog/first/index.html
grep -q '<code>code</code>' dist/blog/first/index.html
grep -q '<ul>' dist/blog/first/index.html
grep -q '<a href="https://example.com">documentation</a>' dist/blog/first/index.html
grep -q '&lt;script&gt;' dist/blog/first/index.html
grep -q '&lt;unsafe&gt;' dist/blog/first/index.html
grep -q '^keep dynamic build directory untouched$' build/app

# Rebuilding the same static site succeeds without cleaning dist/.
"$CLI" site build
# Disallow two sources mapping to the same clean URL.
mkdir -p content/blog/first
printf '# Duplicate\n' > content/blog/first/index.md
if "$CLI" site build; then
  echo 'Expected an output-collision failure' >&2
  exit 1
fi
rm content/blog/first/index.md
# Refuse symlinked input to prevent reading outside the project.
ln -s /tmp content/outside
if "$CLI" site build; then
  echo 'Expected a symlink rejection' >&2
  exit 1
fi
rm content/outside

cd "$WORK"
"$CLI" new dynamic
test -f dynamic/app.mojo
test -f dynamic/mojara.project
cd dynamic
if "$CLI" site build; then
  echo 'Expected static command to reject a dynamic application' >&2
  exit 1
fi

echo 'Mojara static-site CLI smoke checks passed'
