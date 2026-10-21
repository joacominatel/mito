@AGENTS.md

## Claude Code

- Operational facts live in `.claude/charter.md`. Read it before acting.
- Area conventions load automatically from `.claude/rules/` when you touch matching files.
- Project agents (`.claude/agents/`): `swift-core-engineer` implements MitoKit units,
  `macos-ui-engineer` implements app-target units, `test-engineer` audits and closes test
  gaps. Decisions (technology, infrastructure, algorithms) go to the global `analyst`.
- Project skills (`.claude/skills/`): `swift-concurrency`, `swiftui-data-flow`, `liquid-glass`,
  `fitness-functions`.
- The `xcode` MCP server (`.mcp.json`, via `xcrun mcpbridge`) exposes Xcode's documentation
  search, builds, tests, and previews. It needs Xcode open with external agents allowed in
  Settings → Intelligence. Prefer its documentation search over memory for Apple APIs.
- `xcodebuild` needs full Xcode selected (`xcode-select -p`).
