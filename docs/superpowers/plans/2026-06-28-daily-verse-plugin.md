# daily-verse Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin whose `/daily-verse` command reads the user's recent activity, picks a relevant Bible verse, fetches exact wording in their chosen translation, and renders it with a short reflection.

**Architecture:** A slash command (`commands/daily-verse.md`) holds the orchestration prompt (gather → distill → select → fetch → render). A standalone bash helper (`scripts/fetch-verse.sh`) does the deterministic API fetch, so future automation (hook / scheduled agent) can reuse it. Config lives in a `.claude/daily-verse.local.md` file (YAML frontmatter), read at runtime with built-in defaults.

**Tech Stack:** Claude Code plugin format (`.claude-plugin/plugin.json`, `commands/`, `scripts/`); bash + `curl` + `jq`; bible-api.com (public-domain translations, no key) and optionally api.esv.org (keyed). macOS/Linux.

## Global Constraints

- Plugin name: `daily-verse` (used verbatim in `plugin.json`, config filename `.claude/daily-verse.local.md`, and command `/daily-verse`).
- Default translation: `web` (World English Bible). Public-domain options: `web`, `kjv`, `asv`, `bbe`.
- No required credentials. Only the optional ESV path uses a key (`esv_api_key`).
- Privacy: only the selected verse **reference string** may leave the machine. Never send transcript/commit/connector content to any API.
- Helper script invoked via `${CLAUDE_PLUGIN_ROOT}/scripts/fetch-verse.sh`.
- Dependencies assumed present: `bash`, `curl`, `jq` (all confirmed available on the target machine).
- All shell scripts: `#!/usr/bin/env bash` with `set -euo pipefail`.
- Commit after each task.

---

### Task 1: Plugin scaffold and manifest

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.gitignore`
- Create: `scripts/.gitkeep` (placeholder so dir exists; removed in Task 2)

**Interfaces:**
- Consumes: nothing.
- Produces: a valid plugin manifest discoverable by Claude Code; plugin name `daily-verse`.

- [ ] **Step 1: Write the manifest**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "daily-verse",
  "version": "0.1.0",
  "description": "Reads what you've worked on recently and gives a relevant Bible verse with a short reflection.",
  "author": {
    "name": "Miles Maroney",
    "email": "miles@milesmaroney.com"
  }
}
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
# Local user config (never commit personal settings/keys)
.claude/daily-verse.local.md
.DS_Store
```

- [ ] **Step 3: Create scripts dir placeholder**

```bash
mkdir -p scripts && touch scripts/.gitkeep
```

- [ ] **Step 4: Verify the manifest is valid JSON**

Run: `jq empty .claude-plugin/plugin.json && echo OK`
Expected: prints `OK` with no jq error.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .gitignore scripts/.gitkeep
git commit -m "feat: scaffold daily-verse plugin manifest"
```

---

### Task 2: Verse-fetch helper — public-domain path

**Files:**
- Create: `scripts/fetch-verse.sh`
- Create: `tests/fixtures/web-john-3-16.json`
- Create: `tests/test_fetch_verse.sh`
- Delete: `scripts/.gitkeep`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/fetch-verse.sh <reference> [translation]` → prints two lines to stdout: line 1 = canonical reference, line 2+ = verse text (whitespace-trimmed). Exit 0 on success; exit 3 on fetch/parse failure (message on stderr). Honors env override `FETCH_VERSE_MOCK_FILE` (read JSON from that file instead of the network) and `BIBLE_API_BASE` (default `https://bible-api.com`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_fetch_verse.sh`:

```bash
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
```

- [ ] **Step 2: Create the fixture**

Create `tests/fixtures/web-john-3-16.json` (note the literal `\n` newlines inside `text`, matching the real API):

```json
{"reference":"John 3:16","verses":[{"book_id":"JHN","book_name":"John","chapter":3,"verse":16,"text":"\nFor God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.\n\n"}],"text":"\nFor God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.\n\n","translation_id":"web","translation_name":"World English Bible","translation_note":"Public Domain"}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/test_fetch_verse.sh`
Expected: FAIL (script `scripts/fetch-verse.sh` does not exist yet — "No such file or directory").

- [ ] **Step 4: Write the helper script**

Create `scripts/fetch-verse.sh`:

```bash
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
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s '\n' ' ')" \
  || { echo "could not fetch verse (unexpected response)" >&2; exit 3; }

printf '%s\n%s\n' "$out_ref" "$out_text"
```

- [ ] **Step 5: Make it executable and remove the placeholder**

```bash
chmod +x scripts/fetch-verse.sh && git rm -q --cached scripts/.gitkeep 2>/dev/null; rm -f scripts/.gitkeep
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/test_fetch_verse.sh`
Expected: prints `PASS: fetch-verse public-domain path`.

- [ ] **Step 7: (Optional) live smoke check**

Run: `scripts/fetch-verse.sh "John 3:16" web`
Expected: line 1 `John 3:16`; line 2 begins `For God so loved the world`. (Skip if offline — the mocked test already gates correctness.)

- [ ] **Step 8: Commit**

```bash
git add scripts/fetch-verse.sh tests/test_fetch_verse.sh tests/fixtures/web-john-3-16.json
git commit -m "feat: add fetch-verse helper (public-domain translations)"
```

---

### Task 3: ESV support in the helper

**Files:**
- Modify: `scripts/fetch-verse.sh`
- Create: `tests/fixtures/esv-john-3-16.json`
- Modify: `tests/test_fetch_verse.sh`

**Interfaces:**
- Consumes: `scripts/fetch-verse.sh` from Task 2.
- Produces: when `translation` is `esv`, the helper reads key from env `ESV_API_KEY`, calls api.esv.org, and prints `reference\n text` like the public-domain path. Missing key → **exit 4** with stderr message (distinct code so the command can fall back). Honors the same `FETCH_VERSE_MOCK_FILE` override (containing an ESV-shaped JSON) and `ESV_API_BASE` (default `https://api.esv.org/v3/passage/text`).

- [ ] **Step 1: Add failing tests**

Append to `tests/test_fetch_verse.sh` *before* the final `echo "PASS..."` line:

```bash
# 4. ESV: mocked response parses passages[0] + canonical
out="$(ESV_API_KEY=dummy FETCH_VERSE_MOCK_FILE="$HERE/fixtures/esv-john-3-16.json" "$SCRIPT" "John 3:16" esv)"
[ "$(printf '%s' "$out" | sed -n '1p')" = "John 3:16" ] || fail "esv reference wrong: $out"
printf '%s' "$out" | sed -n '2p' | grep -q "For God so loved the world" || fail "esv text missing: $out"

# 5. ESV without key exits 4
set +e
err="$(ESV_API_KEY="" "$SCRIPT" "John 3:16" esv 2>&1 >/dev/null)"
code=$?
set -e
[ "$code" -eq 4 ] || fail "expected exit 4 when ESV key missing, got $code"
printf '%s' "$err" | grep -qi "esv" || fail "missing ESV key message: $err"
```

- [ ] **Step 2: Create the ESV fixture**

Create `tests/fixtures/esv-john-3-16.json` (api.esv.org text-passage shape):

```json
{"query":"John 3:16","canonical":"John 3:16","passages":["For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life."]}
```

- [ ] **Step 3: Run tests to verify the new cases fail**

Run: `bash tests/test_fetch_verse.sh`
Expected: FAIL on case 4 or 5 (ESV branch not implemented; `esv` currently routed to bible-api.com).

- [ ] **Step 4: Implement the ESV branch**

In `scripts/fetch-verse.sh`, replace the fetch+parse section (everything from the `if [[ -n "${FETCH_VERSE_MOCK_FILE...` line through the final `printf`) with:

```bash
if [[ "$translation" == "esv" ]]; then
  : "${ESV_API_KEY:?}" 2>/dev/null || { echo "esv translation requires esv_api_key" >&2; exit 4; }
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
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s '\n' ' ')" \
    || { echo "could not fetch verse (unexpected ESV response)" >&2; exit 3; }
  printf '%s\n%s\n' "$out_ref" "$out_text"
  exit 0
fi

enc_ref="${ref// /%20}"
if [[ -n "${FETCH_VERSE_MOCK_FILE:-}" ]]; then
  resp="$(cat "$FETCH_VERSE_MOCK_FILE" 2>/dev/null)" \
    || { echo "could not fetch verse (mock file unreadable)" >&2; exit 3; }
else
  resp="$(curl -fsS --max-time 12 "${base}/${enc_ref}?translation=${translation}")" \
    || { echo "could not fetch verse from ${base}" >&2; exit 3; }
fi

out_ref="$(printf '%s' "$resp" | jq -er '.reference' 2>/dev/null)" \
  || { echo "could not fetch verse (unexpected response)" >&2; exit 3; }
out_text="$(printf '%s' "$resp" | jq -er '.text' 2>/dev/null \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s '\n' ' ')" \
  || { echo "could not fetch verse (unexpected response)" >&2; exit 3; }

printf '%s\n%s\n' "$out_ref" "$out_text"
```

Also move the `enc_ref` assignment out of the old position (it now lives in the public-domain branch above) — confirm there is no duplicate `enc_ref=` line earlier in the file.

- [ ] **Step 5: Run tests to verify all pass**

Run: `bash tests/test_fetch_verse.sh`
Expected: prints `PASS: fetch-verse public-domain path` (all 5 cases passed).

- [ ] **Step 6: Commit**

```bash
git add scripts/fetch-verse.sh tests/test_fetch_verse.sh tests/fixtures/esv-john-3-16.json
git commit -m "feat: add optional ESV translation support to fetch-verse"
```

---

### Task 4: Config example and loader contract

**Files:**
- Create: `examples/daily-verse.local.md`
- Create: `tests/test_config_example.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: a documented config template users copy to `~/.claude/daily-verse.local.md` or `<project>/.claude/daily-verse.local.md`. Defines the exact frontmatter keys the command (Task 5) reads: `translation`, `esv_api_key`, `sources.session_history`, `sources.git`, `sources.connectors`, `reflection`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_config_example.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_config_example.sh`
Expected: FAIL with "example config missing".

- [ ] **Step 3: Write the example config**

Create `examples/daily-verse.local.md`:

```markdown
---
translation: web        # public-domain: web | kjv | asv | bbe (or "esv" with a key below)
esv_api_key: ""         # optional; get a free key at https://api.esv.org/ to use translation: esv
sources:
  session_history: true # scan ~/.claude/projects transcripts from today/yesterday
  git: true             # scan `git log` of the current repo, if you're in one
  connectors: false     # opt-in: query connected MCP tools (Drive/Gmail/Calendar/journal)
reflection: true        # include a 2-3 sentence reflection tying the verse to your day
---

# daily-verse settings

Copy this file to one of:

- `~/.claude/daily-verse.local.md` (applies everywhere), or
- `<your-project>/.claude/daily-verse.local.md` (per-project override; takes precedence)

Then run `/daily-verse`. Everything above is optional — with no config file the
plugin uses these same defaults (WEB translation, session history + git on,
connectors off, reflection on).
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_config_example.sh`
Expected: prints `PASS: config example`.

- [ ] **Step 5: Commit**

```bash
git add examples/daily-verse.local.md tests/test_config_example.sh
git commit -m "feat: add daily-verse config example and loader contract"
```

---

### Task 5: The `/daily-verse` command

**Files:**
- Create: `commands/daily-verse.md`
- Create: `tests/test_command_frontmatter.sh`

**Interfaces:**
- Consumes: `scripts/fetch-verse.sh` (via `${CLAUDE_PLUGIN_ROOT}`); config keys from Task 4; exit codes 3 (fetch fail) and 4 (ESV key missing).
- Produces: the `/daily-verse` slash command.

- [ ] **Step 1: Write the failing test**

Create `tests/test_command_frontmatter.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_command_frontmatter.sh`
Expected: FAIL with "command file missing".

- [ ] **Step 3: Write the command**

Create `commands/daily-verse.md`:

```markdown
---
description: Reads what you've worked on recently and gives a relevant Bible verse with a short reflection.
---

You are producing today's relevant Bible verse for the user. Follow these steps in order.

## 1. Load config

Read the first file that exists, else use defaults:
1. `./.claude/daily-verse.local.md` (current project)
2. `~/.claude/daily-verse.local.md` (global)

Parse the YAML frontmatter. Defaults if no file/key:
`translation: web`, `esv_api_key: ""`, `sources.session_history: true`,
`sources.git: true`, `sources.connectors: false`, `reflection: true`.

## 2. Gather signals (today and yesterday only)

Only from sources enabled in config:

- **session_history**: List recent files under `~/.claude/projects/` modified in the
  last 2 days (`find ~/.claude/projects -name '*.jsonl' -mtime -2`). Skim the most
  recent few for what the user was working on and struggling with. Do NOT dump full
  transcripts — extract themes only.
- **git**: If the current directory is a git repo, run
  `git log --since=2.days --pretty=format:'%s' 2>/dev/null` for recent work.
- **connectors**: Only if `connectors: true`. Use available MCP tools
  (Drive/Gmail/Calendar/journal) to look for recent entries. If none are connected
  or authorized, skip silently.

If no signals surface (quiet day), proceed with a general theme of encouragement.

## 3. Distill themes

Summarize the day into 1-3 short themes (e.g. "debugging frustration", "a hard
decision", "patience under load"). Keep this internal/brief.

## 4. Select a verse

Choose ONE Bible verse reference that genuinely speaks to those themes. Decide the
reference yourself (e.g. `Philippians 4:6-7`).

## 5. Fetch exact text

Run the helper (this is the ONLY thing that touches the network — it sends only the
reference string, never the user's content):

​```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/fetch-verse.sh" "<reference>" "<translation>"
​```

For `translation: esv`, first export the key from config:
`ESV_API_KEY="<esv_api_key>"` before calling the helper.

Handle exit codes:
- **exit 4** (ESV key missing): re-run the helper with `web` and tell the user ESV
  needs a key, so you fell back to WEB.
- **exit 3** (fetch failed, e.g. offline): tell the user the API was unreachable,
  then quote the verse from your own knowledge and clearly label it
  *(unverified — could not reach the Bible API)*.

The helper prints line 1 = canonical reference, line 2 = verse text.

## 6. Render

Output, using the fetched reference and text:

> **<reference> (<translation, uppercased>)**
> *<verse text>*

Then, if `reflection: true`, add 2-3 sentences connecting the verse to the day's
themes — warm, specific, not preachy. Skip the reflection entirely if
`reflection: false`.

Never print raw transcript contents or commit diffs back to the user — only the
distilled verse and reflection.
```

Note: the `​` characters before the inner ` ```bash ` fences above are zero-width and must NOT be copied — write a normal nested code fence. (If your editor preserves them, delete them.) The intent is a fenced bash block inside the command markdown.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_command_frontmatter.sh`
Expected: prints `PASS: command frontmatter`.

- [ ] **Step 5: Verify the nested code fence is clean**

Run: `grep -n $'​' commands/daily-verse.md || echo "no zero-width chars"`
Expected: prints `no zero-width chars`. If any are found, delete them so the bash block renders normally.

- [ ] **Step 6: Commit**

```bash
git add commands/daily-verse.md tests/test_command_frontmatter.sh
git commit -m "feat: add /daily-verse command"
```

---

### Task 6: Test runner, README, and validation

**Files:**
- Create: `tests/run.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: all prior tests.
- Produces: one entrypoint `bash tests/run.sh` that runs every test; user-facing docs.

- [ ] **Step 1: Write the test runner**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for t in "$HERE"/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t"
done
echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run the full suite**

Run: `bash tests/run.sh`
Expected: each test prints its `PASS:` line, then `ALL TESTS PASSED`.

- [ ] **Step 3: Write the README**

Create `README.md`:

```markdown
# daily-verse

A Claude Code plugin. Run `/daily-verse` and it reads what you've been working on
recently (your Claude Code session history, recent git commits, and — if you opt in —
connected tools like Drive/Gmail/Calendar), distills the themes, and gives you a
relevant Bible verse with a short reflection.

## Install

Add this plugin to Claude Code (e.g. via your plugin marketplace or a local path),
then run `/daily-verse`.

Requires `bash`, `curl`, and `jq` on your PATH.

## Configuration (optional)

Copy `examples/daily-verse.local.md` to `~/.claude/daily-verse.local.md` (global) or
`<project>/.claude/daily-verse.local.md` (per-project). Settings:

| Key | Default | Notes |
|-----|---------|-------|
| `translation` | `web` | `web`, `kjv`, `asv`, `bbe`, or `esv` (needs key) |
| `esv_api_key` | `""` | Free key from https://api.esv.org/ |
| `sources.session_history` | `true` | Scan recent Claude Code transcripts |
| `sources.git` | `true` | Scan recent git commits in the current repo |
| `sources.connectors` | `false` | Opt-in MCP connectors |
| `reflection` | `true` | Include a 2-3 sentence reflection |

With no config file, the defaults above apply — no setup or credentials needed.

## Privacy

Your activity stays on your machine. Only the chosen verse **reference** (e.g.
"Philippians 4:6") is sent to the Bible API — never your transcripts, commits, or
connector data.

## Translations

Free public-domain translations (WEB, KJV, ASV, BBE) come from bible-api.com with no
key. ESV is optional and uses your own free api.esv.org key. NIV is not available
(not freely licensable).

## Development

Run the test suite: `bash tests/run.sh`
```

- [ ] **Step 4: Commit**

```bash
git add tests/run.sh README.md
git commit -m "docs: add test runner and README"
```

- [ ] **Step 5: Validate the plugin**

Dispatch the `plugin-dev:plugin-validator` agent against this repo to check the
manifest and structure. Address any errors it reports (fix + re-run). Expected: no
structural errors.

- [ ] **Step 6: Manual dry-run (acceptance)**

In a real Claude Code session with recent activity, run `/daily-verse`. Confirm:
it produces a themed verse + reflection, the verse text matches the configured
translation, and no transcript/commit content is echoed back. Note the result.

---

## Self-Review

**Spec coverage:**
- Slash command `/daily-verse` → Task 5. ✓
- Live API fetch via helper script → Tasks 2-3. ✓
- Configurable translation incl. optional ESV → Tasks 3-4. ✓
- Config via `.claude/daily-verse.local.md` frontmatter + defaults → Tasks 4-5. ✓
- Signals: session history + git + opt-in connectors → Task 5 step 2. ✓
- Distill → select → fetch → render with reflection → Task 5. ✓
- Error handling (API fail = exit 3 fallback; ESV-no-key = exit 4 fallback; quiet day) → Tasks 2,3,5. ✓
- Privacy (only reference leaves machine) → Task 5 + README. ✓
- Build/validate via plugin-dev tooling → Task 6 step 5. ✓
- Manifest/structure → Task 1. ✓
- Modular logic reusable by future automation → helper script (Tasks 2-3) + prompt-in-command. ✓

**Placeholder scan:** No TBD/TODO. The `<reference>`/`<translation>` tokens in the command markdown are intentional runtime placeholders Claude fills, not plan gaps.

**Type consistency:** Helper contract (args `<reference> [translation]`, output `reference\n text`, exit codes 3/4, env `FETCH_VERSE_MOCK_FILE`/`BIBLE_API_BASE`/`ESV_API_KEY`/`ESV_API_BASE`) is identical across Tasks 2, 3, 5. Config keys identical across Tasks 4 and 5.
