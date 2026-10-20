# AGENTS.md

# Mito

A native macOS companion for League of Legends. It talks to the official client through its
local API (LCU), recommends picks and bans in champ select, imports runes, spells, and item
sets adapted to the matchup, and shows an explainable pre-game analysis. Statistics come from
our own Python pipeline, which publishes a per-patch SQLite snapshot the app downloads. Every
recommendation must be explainable — no black-box "play Ahri".

## Before any change

`MITO_CONTEXT.md` is the source of truth for scope, architecture, APIs, algorithms, and the
roadmap. It is long and in Spanish: use its index and read the sections for the affected area,
not the whole file. When it and the code disagree, the document wins — then correct both.

`.claude/charter.md` carries the operational facts: branches, prefixes, lanes, shared critical
files, validation commands, and the review dimensions every change must clear. **Read it
first.**

1. Investigate the code for what was asked, and read the matching `MITO_CONTEXT.md` sections.
2. Contextualize before editing. No changes from a cold start.
3. When a decision is needed and there is no reference to follow, **ask**. Anything touching
   the snapshot schema, personal data, deletion, security, or Riot policy is escalated before
   acting, not after.

## Workflow

Pre-beta: commit by responsibility directly on `dev` and push to `origin/dev`. No issues, no
PRs. Never touch `main`. The charter has the specifics.

## Riot policy is non-negotiable

Riot is closing third-party access and will keep doing so. Mito stays on the safe side:

- Only the LCU, Live Client Data (v2), the public Riot API, Data Dragon, and CommunityDragon.
- Zero memory reads or writes, zero injection, zero hooks into the game process.
- Nothing automated inside a match.
- Never try to de-anonymize players during champ select. Analysis uses champions and roles.
- The Riot API key lives only in the pipeline. Never in the app, never in the repo.
- Auto-pick and auto-ban, if they exist, are off by default and need explicit confirmation.
- No Riot trademarks in the app's name or icon.

A change that cannot be squared with `MITO_CONTEXT.md` §5 does not ship.

## Tests from day one

Every behavior gets a behavior-focused test in the same change. LCU payloads are tested
against recorded fixtures, never against a live client. Dispatch the `test-engineer` agent to
audit coverage and close gaps after any non-trivial unit.

## Documentation stays in sync

Any change to behavior reviews and updates the affected `MITO_CONTEXT.md` sections in the same
change. Durable decisions get an ADR in `docs/adr/`.

## External libraries

Check current official documentation before using or upgrading a library (GRDB, Sparkle,
DuckDB, Polars, and especially LCU endpoints). Do not rely on memory; these move.

## Definition of done

Code in place, tests passing with the charter's validation commands, documentation
synchronized, every review dimension addressed, and commits scoped and correctly prefixed.
