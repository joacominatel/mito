---
paths:
  - "apps/macos/**"
---

# macOS app conventions

Governing sections: `MITO_CONTEXT.md` §7, §9, §10–13, §18, §22.

## Boundaries

- Logic lives in the local packages; the app target only wires features, views, and
  `AppModel`. Dependency direction: `MitoCore` ← `LCUKit`, `MitoStore`, `MitoEngine` ←
  `MitoAssets` ← app. Never the reverse.
- `MitoCore` has no dependencies. `MitoEngine` is pure: it receives a `DraftContext` and a
  `StatsProvider` protocol and returns recommendations with reasons. No network, no UI, no
  store access.
- Every LCU access goes through the `LCUClient` actor, through typed endpoints. No raw path
  strings scattered across the app.
- Each feature has an `@Observable` model plus views. No logic in views.

## Swift

- Swift 6 with strict concurrency. No `@unchecked Sendable` without a one-line justification.
- `@Observable`, async/await, and actors. Combine only where a framework forces it.
- No `fatalError`, `try!`, or force unwraps on runtime paths. Typed errors (`LCUError`,
  `StoreError`, `EngineError`).
- LCU `Codable` models are tolerant: optional fields, and enums with an `.unknown(String)`
  case. Riot changes payloads without notice.
- Logging with `os.Logger`, one category per module. PUUIDs and names use
  `privacy: .private`. The LCU token is never logged.
- Distribution is outside the Mac App Store; the App Sandbox stays off. Do not add
  entitlements without an ADR.

## UI

- SwiftUI only, no webviews. It must feel like an Apple app: sidebar, toolbar, standard
  Settings, keyboard shortcuts, light/dark, VoiceOver.
- User-facing strings go through `Localizable.xcstrings`, Spanish (es-AR) source. Numbers use
  locale formatters.
- Semantic color never stands alone: pair it with an icon or a sign (+/−).

## Tests

- Swift Testing (`import Testing`, `@Test`, `#expect`) for packages; XCTest only for UI tests.
- Tests live in `Packages/<Name>/Tests/<Name>Tests/`. Run with
  `swift test --package-path apps/macos/Packages/<Name>`.
- LCU decoding is tested against recorded JSON fixtures, including unknown fields and enum
  values. The engine is tested with an in-memory `StatsProvider`.
