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

## License

MIT — see [LICENSE](LICENSE).
