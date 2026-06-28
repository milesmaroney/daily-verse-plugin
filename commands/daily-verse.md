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

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/fetch-verse.sh" "<reference>" "<translation>"
```

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
