#!/usr/bin/env bash
# Fetch exact verse text for a reference + translation.
# Usage: fetch-verse.sh <reference> [translation]
# Output: line 1 = canonical reference, line 2+ = verse text (trimmed).
# Exit 3 on fetch/parse failure.
set -euo pipefail

ref="${1:?usage: fetch-verse.sh <reference> [translation]}"
translation="${2:-web}"
base="${BIBLE_API_BASE:-https://bible-api.com}"

# URL-encode spaces in the reference.
enc_ref="${ref// /%20}"

if [[ -n "${FETCH_VERSE_MOCK_FILE:-}" ]]; then
  resp="$(cat "$FETCH_VERSE_MOCK_FILE" 2>/dev/null)" \
    || { echo "could not fetch verse (mock file unreadable)" >&2; exit 3; }
else
  resp="$(curl -fsS --max-time 12 "${base}/${enc_ref}?translation=${translation}")" \
    || { echo "could not fetch verse from ${base}" >&2; exit 3; }
fi

# Parse with jq; .reference and .text, trim surrounding whitespace on text.
out_ref="$(printf '%s' "$resp" | jq -er '.reference' 2>/dev/null)" \
  || { echo "could not fetch verse (unexpected response)" >&2; exit 3; }
out_text="$(printf '%s' "$resp" | jq -er '.text' 2>/dev/null \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s '\n' ' ' \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" \
  || { echo "could not fetch verse (unexpected response)" >&2; exit 3; }

printf '%s\n%s\n' "$out_ref" "$out_text"
