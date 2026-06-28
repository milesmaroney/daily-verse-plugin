#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for t in "$HERE"/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t"
done
echo "ALL TESTS PASSED"
