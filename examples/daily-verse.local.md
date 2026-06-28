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
