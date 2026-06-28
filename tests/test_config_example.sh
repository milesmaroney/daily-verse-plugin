#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/../examples/daily-verse.local.md"
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$F" ] || fail "example config missing"
# Frontmatter fences present
[ "$(sed -n '1p' "$F")" = "---" ] || fail "must open with --- frontmatter fence"
# Required keys present in frontmatter
for key in "translation:" "esv_api_key:" "session_history:" "git:" "connectors:" "reflection:"; do
  grep -q "$key" "$F" || fail "missing key: $key"
done
# Default translation documented as web
grep -qE "translation:[[:space:]]*web" "$F" || fail "default translation should be web"
echo "PASS: config example"
