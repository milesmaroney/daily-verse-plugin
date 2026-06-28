# daily-verse plugin — design

**Date:** 2026-06-28
**Status:** Approved (brainstorm); pending spec review

## Summary

A Claude Code plugin exposing a `/daily-verse` slash command. When run, Claude
reads what the user has been wrestling with over the last day or two, distills it
into one to three themes, selects a fitting Bible verse, fetches the exact wording
in the user's preferred translation from a live API, and presents the verse plus a
short (2-3 sentence) reflection tying it to the day.

Built as a slash command now, with the orchestration logic kept in the command
prompt so a SessionStart hook or scheduled agent can reuse the same flow later
(automation is out of scope for v1).

## Goals

- One-command daily relevant verse: `/daily-verse`.
- "Relevance" derived from real signals about the user's day, not a generic
  rotation.
- Exact, correctly-attributed verse text via a live Bible API.
- Configurable translation (public-domain options; optional ESV key).
- Modular logic so automation (hook / scheduled agent) can be added later without
  rework.

## Non-goals (v1 — YAGNI)

- Automatic/scheduled delivery (hook, cron, email, notification). Designed for, not
  built.
- Copyrighted translations beyond optional user-supplied ESV key (NIV etc. are not
  freely licensable).
- A web UI or history/journaling of past verses.

## Architecture

Four small pieces, following the plugin-dev `plugin-structure` conventions:

1. **Plugin manifest** — `.claude-plugin/plugin.json`. Standard metadata
   (name, version, description, author).
2. **The command** — `commands/daily-verse.md`. The orchestration prompt that
   tells Claude the steps: gather → distill → select → fetch → render. Keeping the
   logic here (rather than in code) is what lets a future hook or scheduled agent
   invoke the identical flow.
3. **Verse-fetch helper** — `scripts/fetch-verse.sh`. A small script taking a
   reference + translation and returning exact verse text from `bible-api.com`.
   Deterministic and reusable by future automation. Invoked via
   `${CLAUDE_PLUGIN_ROOT}/scripts/fetch-verse.sh`.
4. **Config** — `.claude/daily-verse.local.md`, using the plugin-dev
   `plugin-settings` pattern: YAML frontmatter for settings plus markdown notes.
   Supports per-project overrides. Ships with sensible defaults so the plugin works
   with zero setup.

### Config schema (`.claude/daily-verse.local.md` frontmatter)

```yaml
---
translation: web          # public-domain: web | kjv | asv | bbe
esv_api_key: ""           # optional; enables ESV when set
sources:
  session_history: true   # ~/.claude/projects transcripts (today/yesterday)
  git: true               # git log of current repo, if in one
  connectors: false       # opt-in MCP connectors (Drive/Gmail/Calendar/journal)
reflection: true          # include 2-3 sentence reflection
---
```

Defaults if the file is absent: WEB translation, session_history + git on,
connectors off, reflection on.

## Data flow

1. **Read config** — load `.claude/daily-verse.local.md` frontmatter, or fall back
   to defaults.
2. **Gather signals** over today/yesterday, per enabled sources:
   - *Native:* recent Claude Code transcripts in `~/.claude/projects/`, filtered by
     timestamp; and `git log --since=2.days` of the current repo if in one.
   - *Optional connectors:* if `connectors: true` and authorized, query available
     MCP tools (Drive/Gmail/Calendar/journal) for recent entries.
3. **Distill** into 1-3 themes (e.g. "debugging frustration," "a hard decision,"
   "patience").
4. **Select** a fitting verse reference from the themes.
5. **Fetch** exact text in the configured translation via
   `scripts/fetch-verse.sh "<reference>" "<translation>"`.
6. **Render** to the terminal: reference + verse text + (if enabled) a 2-3 sentence
   reflection connecting it to the day.

## Error handling

- **API / network failure** → fall back to Claude's own recollection of the verse
  text, clearly flagged as unverified.
- **ESV requested but no key** → fall back to the default public-domain translation
  with a note to the user.
- **Quiet day / no discernible themes** → select a general verse of encouragement.
- **No git repo / connectors unavailable** → silently skip that source; proceed
  with whatever signals are available.

## Privacy

The user's day-content (transcripts, commits, connector data) stays local. Only the
selected **verse reference string** (e.g. `Philippians 4:6`) is sent to the Bible
API. No personal content leaves the machine.

## Translation notes

Free, no-key APIs (bible-api.com) serve only **public-domain** translations
(WEB, KJV, ASV, BBE). Copyrighted translations (NIV, ESV) are not freely available;
ESV offers its own keyed API, supported optionally via `esv_api_key`. NIV is not
supported. Default: **WEB** (World English Bible) — modern, readable, public domain.

## Build & validation approach

- Implement using the plugin-dev skills: `plugin-structure`,
  `command-development`, `plugin-settings`.
- Run the `plugin-dev:plugin-validator` agent against the manifest and structure
  before shipping.

## Testing

- **Helper script:** unit-test `fetch-verse.sh` against a known reference/translation
  (assert exact returned text), plus an offline/failure path.
- **Command dry-run:** invoke `/daily-verse` in a session with known recent activity;
  verify it produces a themed verse + reflection and that only the reference would
  hit the network.
- **Config:** verify defaults apply when `.local.md` is absent, and that an
  overridden `translation` is honored.

## Future work (not v1)

- SessionStart hook: show the verse once per day on the first session.
- Scheduled cloud agent: deliver at a set time via notification/email.
- A "verse of the day" history file.
