---
name: fitness-functions
description: Write architecture fitness functions — deterministic tests that enforce a project's hard rules (module boundaries, offline guarantees, content contracts) from inside its own test target. Use when a constraint lives only in prose (CLAUDE.md, code review) and should become un-arguable.
allowed-tools: [Read, Edit, Glob, Grep]
source: rshankras/claude-code-apple-skills@9ffb831 skills/testing/fitness-functions (MIT, adapted)
---

# Architecture Fitness Functions

A fitness function is an ordinary test that enforces an architectural rule instead of a behavior. It lives in a normal test target, runs under every existing test gate, and turns "the agent said it's fine" into an exit code. It covers invariants no behavior test can see: a file quietly importing a framework it must not touch, a secret reaching a log line, a count drifting from its documented size.

## When This Skill Activates

- A hard rule exists only in prose — `AGENTS.md`, `.claude/rules/macos.md`, the charter's review dimensions, `MITO_CONTEXT.md`
- A code review keeps re-checking the same structural rule by hand
- A boundary, count, or content format was broken silently once already

## Mito's Fitness Functions

| Rule | Source | Pattern | Template |
|---|---|---|---|
| The LCU token is never logged: no logging call interpolates a token, password, secret, credential, or authorization value | charter, Security; `.claude/rules/macos.md` | 1 — API-surface scan | `SourceHygieneTests.swift` |
| No `print(` in shipped sources (app target and every MitoKit target) | `.claude/rules/macos.md`, Logging | 1 — API-surface scan | `SourceHygieneTests.swift` |
| `URLSession` is used only in LCUKit and MitoStore | `MITO_CONTEXT.md` §7 boundaries | 1 — API-surface scan | `ImportBoundaryTests.swift` |
| MitoEngine imports only MitoCore and Foundation — nothing networked, no store, no UI | `.claude/rules/macos.md`, Boundaries | 1 — import allowlist | `ImportBoundaryTests.swift` |
| LCUKit talks only to `127.0.0.1`; a cached snapshot load makes no request | charter, Security | 2 — runtime sentinel | `NetworkSentinelTests.swift` |

All source scans share `templates/SourceTree.swift`. It assumes the `apps/macos/MitoKit` package (`Sources/<Target>/`, `Tests/<Target>Tests/`) with the app target at `apps/macos/Mito/`. Copy the files into one MitoKit test target; they need no dependency on the code they scan.

## Why a Test, Not a Lint Rule

A per-line regex (SwiftLint `custom_rules`) can flag a *line*. A fitness function can assert a *set* or a cross-file fact: "MitoEngine's imports are a subset of these two", "every LCU request went to loopback". It rides the `swift test` gate that already exists — no new tooling, no CI wiring.

## The Three Patterns

### Pattern 1: Import Allowlist and API-Surface Scan

Walks the shipped source tree and compares what is there against the contract.

- **Resolve the source root from `#filePath`**, never a hardcoded path. `SourceTree` walks up from the test file to the nearest `Package.swift`, so `Tests/<X>Tests/` resolves to `../../Sources/<X>/` from any checkout.
- **Parse import declarations, not substrings.** With `InternalImportsByDefault` and `@preconcurrency`, imports come as `public import X`, `@preconcurrency import X`, `import struct X.Y`; `SourceFile.importedModules` handles all of them and ignores comments.
- **Report every offender with file and line**, and tell the fixer which side to change: the code, or the contract (with where it is documented).
- **Fence the API, not just the import.** Every file imports Foundation, which is enough to reach `URLSession`; scan for the API itself.
- **The allowlist is a fence, not a headcount.** Widening it is a documented decision: when a file genuinely belongs inside, the failing test is the system working — record why, then widen.
- **Skip comments, keep strings.** Interpolations inside log messages are exactly what the token scan must see.

Templates: `templates/ImportBoundaryTests.swift`, `templates/SourceHygieneTests.swift`

### Pattern 2: Runtime Sentinel

Enforces what a path *attempts*, which is stronger than what happens to succeed. A `URLProtocol` subclass records every request and fails it; the test drives the real production path and asserts on the record.

- **Inject the sentinel through `URLSessionConfiguration.protocolClasses`**, never `URLProtocol.registerClass`: registration is process-global and misses sessions built from their own configuration. Production types therefore take a `URLSessionConfiguration` in `init` — LCUClient needs that seam anyway to install its loopback-only TLS delegate.
- **Shared static state is a `Mutex`, and every test that reads it lives in one `@Suite(.serialized)`.** No `nonisolated(unsafe)`; no second suite touching the same log.
- **Fail requests loudly** so nothing reaches a real server, and assert on attempts, not successes.
- **Prove the path ran**: a loopback-only assertion over zero requests proves nothing, so also assert the record is non-empty.
- **Drive the real path** — real client, real composition — with only storage in memory and LCU payloads from recorded fixtures.

Template: `templates/NetworkSentinelTests.swift`

### Pattern 3: Contract Pins

Pins facts that must change *deliberately*: registry sizes, schema versions, content-format rules iterated over `CaseIterable`, and a few verbatim exemplars. Each pinned number carries a comment trail with its history, so updating it is a reviewed decision with a reason.

Template: `templates/ContractPinTests.swift`

## Process

1. **Identify the invariant.** Good candidates state a set or bound: "only", "never", "exactly", "every".
2. **Pick the pattern.** Which files may use an API → 1. What a path may do at runtime → 2. A size, format, or exact content → 3.
3. **Write the suite.** Copy the template, adapt the `ADAPT` points, name the suite after the guarantee. Templates hold to Mito's rules: no `try!`, force unwraps, or `Thread.sleep`.
4. **Prove it red.** Introduce the violation for real (a `print(` in MitoAssets, `import Network` in MitoEngine, a logger line interpolating the token), run `swift test`, confirm the failure names the offender, revert, confirm green. Repeat whenever the scanning logic changes.
5. **Commit** with the red/green pair in the message.

## Output Format

```markdown
## Fitness Function: [invariant]

- **Rule source**: [charter dimension / rules file / MITO_CONTEXT.md section]
- **Pattern**: import allowlist | API-surface scan | runtime sentinel | contract pin
- **Suite**: Tests/[Target]Tests/[Name]Tests.swift
- **Deliberate-break drill**: [what was broken] → failed with "[message]" → reverted → green
```

## Common Pitfalls

| Pitfall | Problem | Solution |
|---------|---------|----------|
| `contains("import X")` matching | Comments about the rule count; `public import X` is missed | Parse declarations (`SourceFile.importedModules`) |
| Hardcoded source paths | Breaks on other checkouts and CI | Resolve from `#filePath` |
| Line-only log scan | Multi-line `Logger` calls slip through | Scan the balanced call arguments |
| `URLProtocol.registerClass` | Global, racy, misses custom configurations | Inject `protocolClasses` |
| `nonisolated(unsafe)` static counters | Data race across parallel tests | `Mutex` plus a `.serialized` suite |
| Never proven red | A scanner bug silently passes everything | Deliberate-break drill before commit |
| Allowlist grows without comment | The fence decays into a headcount | Each entry documents why it is inside |
