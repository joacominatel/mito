# 0004 — Branching and merge strategy

- **Status**: accepted
- **Date**: 2026-10-20

## Context

One developer is building from zero. Issues and pull requests would slow the pre-beta phase,
but history should stay linear and readable, and `main` should only ever hold what was
promoted.

## Decision

- **Pre-beta**: commits land directly on `dev`, one responsibility each, and are pushed to
  `origin/dev`. No feature branches, issues, or pull requests.
- **Promotion**: `dev` reaches `main` only by fast-forward (`git merge --ff-only dev` on
  `main`), performed by the CEO, followed by an annotated tag `vX.Y.Z`. `main` never receives
  its own commits, so a fast-forward is always possible; fixes go to `dev` first.
- **Post-beta**: work moves to short-lived branches with a pull request into `dev`, merged
  with **squash** (one PR = one responsibility = one commit on `dev`). Promotion to `main`
  stays fast-forward only.
- **Never**: force-push to `dev` or `main`, merge commits on `main`, or rewriting published
  history.
- **CI**: tests run on pushes to `main` and `dev` and on pull requests targeting them.

## Consequences

- `main` is a strict prefix of `dev`; every tag on `main` names a tested `dev` commit.
- A hotfix on a released version is cut from the tag, merged into `dev`, then promoted.
