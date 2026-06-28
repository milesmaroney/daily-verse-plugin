#!/usr/bin/env bash
# Fetch exact verse text for a reference + translation.
# Usage: fetch-verse.sh <reference> [translation]
# Output: line 1 = canonical reference, line 2+ = verse text (trimmed).
# Exit 3 on fetch/parse failure.
# Exit 4 when ESV translation requested but ESV_API_KEY is not set.
set -euo pipefail

ref="${1:?usage: fetch-verse.sh <reference> [translation]}"
translation="${2:-web}"
base="${BIBLE_API_BASE:-https://bible-api.com}"

if [[ "$translation" == "esv" ]]; then
  if [[ -z "${ESV_API_KEY:-}" ]]; then
    echo "esv translation requires ESV_API_KEY" >&2; exit 4
  fi
  esv_base="${ESV_API_BASE:-https://api.esv.org/v3/passage/text}"
  if [[ -n "${FETCH_VERSE_MOCK_FILE:-}" ]]; then
    resp="$(cat "$FETCH_VERSE_MOCK_FILE" 2>/dev/null)" \
      || { echo "could not fetch verse (mock file unreadable)" >&2; exit 3; }
  else
    resp="$(curl -fsS --max-time 12 \
      -H "Authorization: Token ${ESV_API_KEY}" \
      --get "$esv_base/" \
      --data-urlencode "q=${ref}" \
      --data-urlencode "include-headings=false" \
      --data-urlencode "include-footnotes=false" \
      --data-urlencode "include-verse-numbers=false" \
      --data-urlencode "include-short-copyright=false" \
      --data-urlencode "include-passage-references=false")" \
      || { echo "could not fetch verse from ESV API" >&2; exit 3; }
  fi
  out_ref="$(printf '%s' "$resp" | jq -er '.canonical' 2>/dev/null)" \
    || { echo "could not fetch verse (unexpected ESV response)" >&2; exit 3; }
  out_text="$(printf '%s' "$resp" | jq -er '.passages[0]' 2>/dev/null \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s '\n' ' ' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" \
    || { echo "could not fetch verse (unexpected ESV response)" >&2; exit 3; }
  printf '%s\n%s\n' "$out_ref" "$out_text"
  exit 0
fi

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
