# 0006 — Parallel unit workflow

- **Status**: accepted
- **Date**: 2026-10-20
- **Amends**: [0004](0004-branching-and-merge-strategy.md), pre-beta clause only

## Context

ADR 0004 put every pre-beta commit directly on `dev`, with no branches. That works for one
author editing one thing at a time. From Phase 1 the roadmap is split into small units that
several agents implement at once; sharing one checkout and one branch would interleave their
edits and make any single unit impossible to review or drop. Issues and pull requests are
still overhead before the beta, and nothing outside this Mac needs to see work in progress.

## Decision

- **Phase 0** stays as ADR 0004 says: commits by responsibility directly on `dev`, pushed to
  `origin/dev`.
- **From Phase 1**, every unit in `docs/roadmap.md` runs on a local branch
  `unit/<id>-<slug>` in a project-local worktree, created from `dev`:
  `git worktree add -b unit/<id>-<slug> .worktrees/<id>-<slug> dev`.
- **Unit branches are never pushed.** No GitHub issues and no pull requests until the beta.
- **Inside the unit**: commits by responsibility; the agent's first write is `.claude/lane`
  with its card's write globs. To catch up with `dev` it runs `git merge dev` in the
  worktree, never a rebase, then re-runs validation.
- **Landing**: the dispatcher lands units one at a time, on `dev` in the main checkout:
  `git merge --squash unit/<id>-<slug>`, update that unit's row in `docs/roadmap.md`, commit
  `<type>(<lane>): <summary>` with `Unit: <id>` in the body, re-run validation, then
  `git push origin dev`. The first unit to land wins a conflict; the later one catches up.
- **Cleanup** after a squash: `git worktree remove .worktrees/<id>-<slug>`,
  `git branch -D unit/<id>-<slug>`, `git worktree prune`, and confirm the main checkout is
  still on `dev`. `git branch -D` is pre-authorized for squashed unit branches only, never
  for `main` or `dev`.
- **Concurrency**: at most 3 units in flight; the cap rises to 4 once three-way parallel
  work has landed cleanly.
- **Pre-launch checks** before a unit starts: its status is `ready`; its write set, the
  `MITO_CONTEXT.md` sections it edits, and its fixture directories are disjoint from every
  unit in flight; it touches no shared critical file unless it runs alone; the main checkout
  is on `dev`, clean, and green; no worktree or branch exists for its id; the cap allows it.
- **Unchanged from 0004**: promotion of `dev` to `main` (CEO only, fast-forward, tag), the
  post-beta return to branches and pull requests, CI triggers, and the prohibition on
  force-pushes and rewriting published history.

## Consequences

- `dev` keeps one commit per unit, so a unit can be reverted as a whole.
- Unit branches exist only on this Mac; losing the machine loses unlanded units, which are
  small by construction.
- `.worktrees/` and `.claude/lane` stay git-ignored.
- Agents validate with the CLI (`swift test`, `xcodebuild`) from their worktree, not through
  the Xcode MCP, which only sees the project Xcode has open.
- Shared critical files force serial work; the charter lists them and the lanes.
