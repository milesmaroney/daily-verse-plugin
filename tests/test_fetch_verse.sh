#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/fetch-verse.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Parses a mocked WEB response into "reference\n text"
out="$(FETCH_VERSE_MOCK_FILE="$HERE/fixtures/web-john-3-16.json" "$SCRIPT" "John 3:16" web)"
[ "$(printf '%s' "$out" | sed -n '1p')" = "John 3:16" ] || fail "reference line wrong: $out"
printf '%s' "$out" | sed -n '2p' | grep -q "For God so loved the world" || fail "verse text missing: $out"
# No leading/trailing blank lines around the text
[ -n "$(printf '%s' "$out" | sed -n '2p')" ] || fail "verse text not on line 2 (untrimmed?): $out"

# 2. Failure path: missing mock file exits 3 with stderr message
set +e
err="$(FETCH_VERSE_MOCK_FILE="$HERE/fixtures/does-not-exist.json" "$SCRIPT" "John 3:16" web 2>&1 >/dev/null)"
code=$?
set -e
[ "$code" -eq 3 ] || fail "expected exit 3 on fetch failure, got $code"
printf '%s' "$err" | grep -qi "could not fetch" || fail "missing error message: $err"

# 3. Missing reference arg exits non-zero
set +e; "$SCRIPT" >/dev/null 2>&1; code=$?; set -e
[ "$code" -ne 0 ] || fail "expected non-zero when reference arg omitted"

echo "PASS: fetch-verse public-domain path"
