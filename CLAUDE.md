@AGENTS.md

## Claude Code

- Operational facts live in `.claude/charter.md`. Read it before acting.
- Area conventions load automatically from `.claude/rules/` when you touch matching files.
- Project agents: `test-engineer` (`.claude/agents/test-engineer.md`).
- `xcodebuild` needs full Xcode. If `xcode-select -p` points at Command Line Tools, prefix
  with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
