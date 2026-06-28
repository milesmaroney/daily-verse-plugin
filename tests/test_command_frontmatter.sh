#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/../commands/daily-verse.md"
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$F" ] || fail "command file missing"
[ "$(sed -n '1p' "$F")" = "---" ] || fail "must open with --- frontmatter fence"
grep -q "^description:" "$F" || fail "missing description in frontmatter"
# References the helper via the plugin root variable
grep -q 'CLAUDE_PLUGIN_ROOT' "$F" || fail "command must call the helper via CLAUDE_PLUGIN_ROOT"
grep -q 'fetch-verse.sh' "$F" || fail "command must invoke fetch-verse.sh"
# Honors config locations
grep -q 'daily-verse.local.md' "$F" || fail "command must read config file"
# Privacy guardrail present
grep -qi 'reference' "$F" || fail "command must mention sending only the reference"
echo "PASS: command frontmatter"
