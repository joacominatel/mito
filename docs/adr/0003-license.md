# 0003 — License

- **Status**: accepted
- **Date**: 2026-10-20

## Context

The code should be public and readable, forkable and modifiable for personal use, and the
author must keep the ability to sell a membership. Nobody else may ship a competing product
built from it, paid or free. OSI open-source licenses cannot express that last constraint.

## Decision

Mito is source-available under the **PolyForm Shield License 1.0.0** (`LICENSE.md`). Any use
is permitted except providing a product that competes with Mito. The name "Mito" and its
assets are not licensed.

## Consequences

- Mito is not "open source" in the OSI sense; public copy must say "source-available".
- Before accepting the first external contribution, a contributor agreement (or contribution
  terms granting the author a broad license) must exist, otherwise contributed code cannot be
  used in the paid offering.
- Third-party material keeps its own license (`.claude/skills/THIRD_PARTY_NOTICES.md`).
- Riot's policies still apply on top: any paid tier needs a registered, approved product and a
  free tier (`MITO_CONTEXT.md` §5).
