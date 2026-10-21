# Mito — Documento de contexto del proyecto

> Companion app nativa de macOS para League of Legends.
> Este documento es la fuente de verdad del proyecto: visión, alcance, arquitectura, datos,
> algoritmos, APIs, reglas de Riot, convenciones y roadmap. Está pensado para que cualquier
> persona (o asistente de IA) que arranque una sesión de trabajo sobre Mito tenga todo el
> contexto necesario sin tener que preguntar.

- **Nombre:** Mito
- **Autor / maintainer:** Joaco (@jminatel)
- **Estado:** idea → arranque (octubre 2026)
- **Plataforma objetivo:** macOS (Apple Silicon primero)
- **Idioma de la UI:** español (es-AR) primero, inglés después
- **Idioma del código:** inglés (identificadores, commits, comentarios técnicos)
- **Idioma de la documentación:** este documento en español; todo lo demás (docs nuevas,
  ADRs, instrucciones de agentes) en inglés

---

## Índice

1. [Visión](#1-visión)
2. [Origen y problema](#2-origen-y-problema)
3. [Qué es y qué NO es Mito](#3-qué-es-y-qué-no-es-mito)
4. [Alcance por versión](#4-alcance-por-versión)
5. [Reglas de Riot y límites no negociables](#5-reglas-de-riot-y-límites-no-negociables)
6. [Arquitectura general](#6-arquitectura-general)
7. [Stack tecnológico](#7-stack-tecnológico)
8. [Estructura del repositorio](#8-estructura-del-repositorio)
9. [La app macOS (mito-app)](#9-la-app-macos-mito-app)
10. [Conexión con el cliente: LCU API](#10-conexión-con-el-cliente-lcu-api)
11. [Flujo de juego (gameflow) y máquina de estados](#11-flujo-de-juego-gameflow-y-máquina-de-estados)
12. [Champ select en detalle](#12-champ-select-en-detalle)
13. [Importación de runas, spells e ítems](#13-importación-de-runas-spells-e-ítems)
14. [Pipeline de datos (mito-data)](#14-pipeline-de-datos-mito-data)
15. [Riot API pública](#15-riot-api-pública)
16. [Datos estáticos: Data Dragon, CommunityDragon y el cliente local](#16-datos-estáticos)
17. [Modelo de datos del snapshot](#17-modelo-de-datos-del-snapshot)
18. [Motor de recomendaciones](#18-motor-de-recomendaciones)
19. [Capa personal](#19-capa-personal)
20. [Pantalla de análisis pre-partida](#20-pantalla-de-análisis-pre-partida)
21. [Configuración y toggles](#21-configuración-y-toggles)
22. [Diseño de UI nativa](#22-diseño-de-ui-nativa)
23. [Testing y entorno de desarrollo](#23-testing-y-entorno-de-desarrollo)
24. [Distribución](#24-distribución)
25. [Seguridad y privacidad](#25-seguridad-y-privacidad)
26. [Roadmap por fases](#26-roadmap-por-fases)
27. [Overlay (v2) — notas para después](#27-overlay-v2--notas-para-después)
28. [Riesgos y preguntas abiertas](#28-riesgos-y-preguntas-abiertas)
29. [Glosario](#29-glosario)
30. [Referencias](#30-referencias)

---

## 1. Visión

Mito es el "Blitz para Mac": una app nativa de macOS que acompaña al cliente oficial de
League of Legends y hace que todo lo que pasa **antes** de la partida sea más inteligente:

- Acepta la partida por vos.
- En champ select te dice **qué elegir** en base a tu pool, a tu historial, al meta, a los
  picks de tu equipo y a los picks del rival.
- Cuando elegís, **importa automáticamente** runas, summoner spells, item sets y orden de
  habilidades, **adaptados a esa partida en particular** (matchup, composición rival, rol).
- Te muestra un **análisis pre-partida** serio: matchup, sinergias, perfil de daño de ambos
  equipos, power spikes, qué ítems situacionales vas a necesitar y por qué.
- Todo es habilitable, deshabilitable y configurable.
- La interfaz es **lo más macOS nativa posible**: SwiftUI, menú en la barra, notificaciones
  del sistema, Settings estándar, SF Symbols, Swift Charts.

Principio rector: **cada recomendación tiene que poder explicarse**. Mito no es una caja
negra que dice "jugá Ahri". Dice "Ahri: 54,1 % de winrate vs Zed en Esmeralda+ (8.200
partidas), es tu tercer campeón más jugado y tu equipo ya tiene mucho daño físico".

---

## 2. Origen y problema

- LoL corre nativo en macOS (Apple Silicon). Mucha gente no lo sabe.
- En Windows el ecosistema de companions es enorme: Blitz, Porofessor, U.GG, Mobalytics.
- En Mac la experiencia es pobre. Blitz funciona en parte (runas sí, overlays no), los
  overlays fallan y nada se siente nativo: son apps Electron/web adaptadas.
- Hueco concreto: **no existe un companion de LoL diseñado para macOS desde cero**.

Joaco usaba mucho Blitz en Windows y lo que más valoraba era:

1. Runas, spells e ítems importados solos.
2. Recomendaciones de campeones.
3. Picks "personales" basados en lo que le gusta jugar.
4. Información útil sobre la partida.

Mito arranca por eso, con el foco puesto en la calidad del análisis pre-partida.

---

## 3. Qué es y qué NO es Mito

### Es

- Un **companion**: proceso separado que se conecta a las APIs locales que expone el cliente
  oficial (LCU) y a datos propios precomputados.
- Una app de **menú en la barra + ventana principal**, nativa de macOS.
- Un **sistema de datos** propio: un pipeline que junta partidas con la Riot API, calcula
  estadísticas por parche y publica un "snapshot" que la app descarga.

### NO es

- **No es un reemplazo del cliente.** El cliente oficial de LoL siempre tiene que estar
  corriendo. Mito lo maneja desde afuera, igual que Blitz o Porofessor.
- **No es una app de iOS.** Es macOS. (Se mencionó "iOS native" al principio, pero el
  objetivo real es Swift/SwiftUI nativo en Mac.)
- **No lee memoria del juego, no inyecta código, no modifica archivos del juego** (salvo los
  que la LCU administra, como item sets, y siempre vía API).
- **No automatiza el gameplay.** Nada dentro de la partida.
- **No es un scraper de u.gg u op.gg.** Los datos son propios.
- **No muestra publicidad** dentro del cliente ni en overlays (Riot lo prohibió en 2025).

---

## 4. Alcance por versión

### v1 — "Pre-game" (foco actual)

| Feature | Descripción | Prioridad |
|---|---|---|
| Conexión LCU | Detectar cliente, autenticar y reconectar | P0 |
| Estado de gameflow | Saber en qué fase está el cliente | P0 |
| Auto-accept | Aceptar ready check, con delay configurable | P0 |
| Lectura de champ select | Picks, bans, roles y timer en tiempo real | P0 |
| Import de runas | Página adaptada a campeón, rol y matchup | P0 |
| Import de spells | Spells recomendados (respetando preferencias D/F) | P0 |
| Import de item sets | Starter, core y situacionales | P0 |
| Orden de habilidades | Mostrado en la UI (y en el item set como bloque informativo) | P1 |
| Recomendación de picks | Ranking de campeones para tu rol en ese draft | P0 |
| Recomendación de bans | Ranking de bans para tu rol y tu pool | P1 |
| Análisis pre-partida | Matchup, sinergias, comps, perfil de daño, spikes | P0 |
| Capa personal | Pool, comfort, rendimiento propio | P0 |
| Historial propio | Últimas partidas con métricas | P1 |
| Control de lobby | Crear lobby, elegir cola y roles, buscar partida desde Mito | P2 |
| Settings completas | Todo con toggle y overrides por campeón | P0 |
| Notificaciones | "Partida aceptada", "Te toca elegir", "Runas importadas" | P1 |

### v2 — "In-game"

- Overlay (ver sección 27).
- Live Client Data API (`127.0.0.1:2999`).
- Post-game: resumen y comparación contra el promedio del campeón.

### Fuera de alcance (por ahora)

- TFT, ARAM-específico (puede llegar fácil después), Arena.
- Windows / Linux.
- Cuentas, login en la nube o sincronización entre dispositivos.
- Monetización.

---

## 5. Reglas de Riot y límites no negociables

Riot viene cerrando el acceso de terceros y lo va a seguir haciendo. Mito tiene que estar
siempre del lado seguro. Estado conocido a octubre de 2026:

- **Anti-cheat en Mac:** desde el parche 25.S1.2 (enero 2025), LoL en macOS usa **Embedded
  Vanguard (mVG)**, integrado dentro de la app. No requiere instalación aparte.
- **Memoria del juego:** Riot anunció que las apps de terceros pierden el acceso a la
  memoria del juego y que las **APIs oficiales son la única vía permitida** para obtener
  datos. Las apps aprobadas tienen hasta abril de 2027 para migrar.
- **Overlays:** la política de Riot habla de overlays que muestran información estática
  disponible antes de la partida. Nada que dé ventaja en vivo que el juego no te da.
- **Publicidad:** desde mayo de 2025 no se permite publicidad de terceros dentro del juego,
  en overlays, en pantallas de carga ni en el Riot Client.
- **Policy general de la API:** no crear juegos con la IP de Riot, nada de cripto o
  blockchain, no actuar como "data broker", no parecerse demasiado a productos de Riot.

### Reglas internas de Mito (derivadas)

1. **Solo APIs oficiales o semi-oficiales**: LCU (local), Live Client Data (local, v2), Riot
   API pública, Data Dragon y CommunityDragon.
2. **Cero lectura o escritura de memoria. Cero inyección. Cero hooks al proceso del juego.**
3. **Nada automatizado dentro de la partida.**
4. **Respetar el anonimato del champ select.** En colas ranked, Riot oculta los nombres
   durante la selección. Mito **no** intenta desanonimizar jugadores (ni aliados ni
   rivales) mientras dure el champ select. El análisis usa campeones y roles, no identidades.
5. **La API key de Riot nunca va dentro de la app.** Solo vive en el pipeline de datos.
6. **El nombre y el ícono no usan marcas de Riot.** "Mito" está bien. No usar "Riot",
   "League" ni logos oficiales como marca de la app. Los íconos de campeones e ítems se usan
   como datos dentro de la UI, que es lo que permite la política para fan apps.
7. **Disclaimer legal** visible en la pestaña "Acerca de" de Settings (`AboutSettingsTab`):
   > Mito isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot
   > Games or anyone officially involved in producing or managing Riot Games properties.
   > Riot Games, and all associated properties are trademarks or registered trademarks of
   > Riot Games, Inc.
8. **Auto-pick y auto-ban:** son features sensibles. Si existen, van **apagadas por
   defecto**, con confirmación explícita. El modo por defecto es "sugerir + un clic".
9. Si Mito se distribuye públicamente: **registrar la app en el Riot Developer Portal** y
   pedir una production key para el pipeline.

---

## 6. Arquitectura general

```
                        ┌──────────────────────────────────────────┐
                        │              mito-data (Python)          │
                        │                                          │
  Riot API  ──────────▶ │  crawler ─▶ raw store ─▶ aggregator ─▶   │
  (match-v5, league-v4) │  (async)    (parquet)    (DuckDB)        │
                        │                              │           │
  Data Dragon / CDragon▶│  static loader ──────────────┤           │
                        │                              ▼           │
                        │                     exporter: snapshot   │
                        │                     .sqlite.xz + tips    │
                        │                     + manifest.json      │
                        └──────────────────────────┬───────────────┘
                                                   │ publish
                                                   ▼
                                   ┌───────────────────────────────┐
                                   │ hosting estático (Cloudflare  │
                                   │ R2)    manifest + .sqlite.xz  │
                                   └───────────────┬───────────────┘
                                                   │ HTTPS (descarga
                                                   │ al abrir / por parche)
                                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        mito-app (Swift, macOS)                           │
│                                                                          │
│  ┌──────────┐   ┌─────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │  LCUKit  │──▶│ GameSession │──▶│   Engine     │──▶│  UI (SwiftUI)  │  │
│  │ REST+WAMP│   │ state mach. │   │ recomendador │   │ menubar+window │  │
│  └────┬─────┘   └─────────────┘   └──────┬───────┘   └────────────────┘  │
│       │                                  │                               │
│       │         ┌────────────────────────┴──────┐                        │
│       │         │ MitoStore (GRDB / SQLite)     │                        │
│       │         │ - snapshot global (read-only) │                        │
│       │         │ - datos personales (local)    │                        │
│       │         │ - settings / overrides        │                        │
│       │         └───────────────────────────────┘                        │
└───────┼──────────────────────────────────────────────────────────────────┘
        │ HTTPS + WSS a 127.0.0.1:<puerto>
        ▼
┌────────────────────────┐
│ League Client (LCUx)   │
└────────────────────────┘
```

### Decisiones clave

- **Snapshot, no backend online (v1).** El pipeline precomputa todo por parche y lo exporta
  a un **archivo SQLite** comprimido por bracket (§14.12). La app lo descarga y consulta
  localmente. Ventajas:
  - Respuesta instantánea en champ select (los timers son de 30 segundos).
  - Funciona offline una vez descargado.
  - No hay servidor que mantener, escalar ni pagar por request.
  - La API key de Riot nunca sale del pipeline.
- **El cálculo de recomendaciones corre en la app (Swift).** El snapshot trae estadísticas
  agregadas y el motor combina eso con el estado del draft y los datos personales en tiempo
  real.
- **Los datos personales se calculan localmente** a partir del historial que da la LCU, sin
  API key. Opcionalmente se enriquecen con más historial vía pipeline.
- **Backend online (opcional, v1.5+):** una API chica (FastAPI) para consultas pesadas o
  datos personales profundos. No es necesario para arrancar.

### Por qué no todo en Swift

- La recolección y agregación de cientos de miles de partidas es trabajo de datos: Python +
  Polars/DuckDB es muchísimo más productivo y Joaco lo maneja mejor.
- Swift queda para lo que tiene que ser nativo: la UI, la conexión con el cliente y el motor
  de decisión en tiempo real.

---

## 7. Stack tecnológico

### mito-app

| Pieza | Elección | Notas |
|---|---|---|
| Lenguaje | Swift 6 | Strict concurrency. App: `MainActor` por defecto + approachable concurrency; MitoKit: nonisolated (ADR 0001) |
| UI | SwiftUI + AppKit puntual | AppKit para el panel del overlay (v2) y algunos detalles de ventana |
| Target | macOS 15+ | Adoptar Liquid Glass y APIs nuevas con `if #available` |
| Estado | `@Observable` (Observation) | Sin Combine salvo donde haga falta |
| Concurrencia | async/await, actors | `LCUClient` como actor |
| Networking | URLSession (REST + `URLSessionWebSocketTask`) | Sin dependencias para la LCU |
| Persistencia | GRDB.swift 7.11.1 sobre SQLite | Lee el snapshot y guarda los datos personales. Versión fija (`exact:`), solo en `MitoStore` (ADR 0008) |
| Gráficos | Swift Charts | Winrate por duración, curvas de oro, etc. |
| Imágenes | AsyncImage + caché en disco propia | Assets del cliente local o de Data Dragon |
| Updates | Sparkle | La app no va al Mac App Store |
| Tests | Swift Testing + XCTest para UI | Mock LCU server para integración |
| Logs | `os.Logger` | Categorías por módulo |
| Build settings | `.xcconfig` en `apps/macos/Config/` | Debug (`com.joacominatel.mito.debug`, "Mito Dev") y Release (ADR 0002) |
| Formato | `swift-format` (incluido en el toolchain) | Config en `apps/macos/.swift-format` |

### mito-data

| Pieza | Elección | Notas |
|---|---|---|
| Lenguaje | Python 3.12+ | |
| Gestor | uv | Lockfile reproducible |
| HTTP | httpx (async) | Con rate limiter propio |
| Estado del crawl | SQLite (o Postgres si crece) | Colas de puuids y matchIds ya vistos |
| Raw store | Parquet (pyarrow) | Particionado por región y parche |
| Agregación | DuckDB + Polars | SQL sobre parquet, rápido y sin servidor |
| Export | sqlite3 + xz | Un `.sqlite.xz` por (schema, parche, cola, bracket) y los tips por locale |
| Validación | pydantic | Modelos de match-v5 |
| CLI | typer | `mito-data crawl`, `aggregate`, `export`, `publish` |
| Scheduling | cron / GitHub Actions / Jenkins | Joaco ya usa Jenkins |
| Publicación | Cloudflare R2 | Hosting estático sin costo de egress (ADR 0005) |

---

## 8. Estructura del repositorio

Este repo contiene la app y sus herramientas. El pipeline de datos vive en un repo privado
aparte, `mito-data` (ADR 0005); los dos se comunican solo a través del snapshot publicado.

```
mito/
├── README.md
├── MITO_CONTEXT.md              ← este documento
├── LICENSE.md                   ← PolyForm Shield 1.0.0 (ADR 0003)
├── apps/
│   └── macos/
│       ├── Mito.xcodeproj       ← grupo sincronizado, sin settings propios
│       ├── Config/              ← Base/Debug/Release/Version .xcconfig
│       ├── Mito/                ← target de la app (UI, App, Scenes)
│       │   ├── MitoApp.swift
│       │   ├── App/             ← AppModel con un slot por feature (ADR 0007)
│       │   ├── Scenes/
│       │   │   ├── MenuBar/
│       │   │   ├── MainWindow/
│       │   │   └── Settings/
│       │   ├── Features/        ← una carpeta y un .xcstrings por feature
│       │   │   ├── Connection/
│       │   │   ├── Gameflow/
│       │   │   ├── ChampSelect/
│       │   │   ├── Import/
│       │   │   ├── Champions/
│       │   │   ├── Analysis/
│       │   │   ├── Profile/
│       │   │   ├── Onboarding/
│       │   │   ├── Overrides/
│       │   │   └── About/
│       │   ├── DesignSystem/
│       │   └── Resources/
│       ├── MitoTests/           ← tests de la app (Swift Testing, hosted)
│       └── MitoKit/             ← un paquete local, un target por módulo (ADR 0002, 0007)
│           ├── Package.swift
│           ├── Sources/
│           │   ├── MitoCore/    ← modelos de dominio, IDs, enums (sin dependencias)
│           │   ├── LCUKit/      ← conexión, REST, WAMP, endpoints tipados
│           │   ├── MitoStore/   ← GRDB, snapshot, datos personales, settings
│           │   ├── MitoEngine/  ← recomendador (puro, testeable)
│           │   ├── MitoAssets/  ← carga y caché de íconos
│           │   └── MitoImport/  ← importador de runas, spells e item sets
│           └── Tests/
│               ├── <Módulo>Tests/      ← uno por módulo
│               ├── MitoTestSupport/    ← fakes y fixtures compartidos
│               └── ArchitectureTests/  ← fitness functions (límites entre módulos)
├── .github/workflows/          ← CI: tests de MitoKit y build + tests de la app en main/dev
├── fixtures/
│   ├── lcu/                     ← grabaciones anonimizadas de la LCU, por escenario
│   └── snapshot/                ← snapshot chico de ejemplo + schema, para el contract test
├── tools/
│   ├── lcu-mock/                ← servidor fake de LCU (Python) para testear la app
│   └── lcu-recorder/            ← graba eventos WAMP reales a fixtures
└── docs/
    ├── adr/                     ← decisiones de arquitectura
    ├── roadmap.md               ← backlog de unidades y su estado
    └── lcu-endpoints.md         ← endpoints descubiertos y probados
```

---

## 9. La app macOS (mito-app)

### 9.1 Escenas

```swift
@main
struct MitoApp: App {
    @State private var app: AppModel

    init() {
        // En Debug, -MitoLCULockfilePath apunta al mock (§23.1).
        let client = AppModel.liveClient()
        // Bajo XCTest no hay cliente en vivo ni archivo de settings real.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let app = AppModel(
            connection: client,
            lifecycle: AppModel.lifecycle(running: client, underTest: underTest),
            settings: SettingsModel(persistence: underTest ? nil : SettingsStore()))
        _app = State(initialValue: app)
        Task { await app.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environment(app)
        } label: {
            MenuBarLabel().environment(app)  // además abre la ventana al entrar a champ select
        }
        .menuBarExtraStyle(.window)

        Window(Text(verbatim: "Mito"), id: "main") {
            MainWindowView().environment(app)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView().environment(app)
        }
    }
}
```

`start()` arranca en el `init` porque la app vive en la barra de menú y no hay ninguna vista
que esté siempre abierta para colgarle un `.task`.

- **MenuBarExtra:** estado de conexión, fase actual, toggles rápidos (auto-accept, auto-runas)
  y el pick recomendado durante champ select.
- **Ventana principal:** se abre sola (configurable) al entrar en champ select. Muestra el
  draft, las recomendaciones y el análisis.
- **Settings:** escena estándar de macOS (⌘,).

### 9.2 Módulos y responsabilidades

| Módulo | Responsabilidad | Depende de |
|---|---|---|
| `MitoCore` | Tipos de dominio: `ChampionID`, `Role`, `PerkID`, `ItemID`, `SummonerSpellID`, `Patch`, `Draft`, `RunePage`, `ItemSet`; el protocolo `StatsProvider` y sus filas (`SnapshotMeta`, `ChampionRoleStats`, candidatos de loadout, relaciones, `ChampionProfile`, `EnemyProfile`, `ChampionFlag`, `DurationBucket`, `Tier`, `SampleLevel`); la explicación (`Reason`, `PickRecommendation`, `BanRecommendation`); el protocolo `PersonalStore` y sus registros (`MyMatch`, `MyMatchParticipant`, `ChampionOverride`, `PoolEntry`, `ImportLogEntry`) | nada |
| `LCUKit` | Descubrir el cliente, credenciales, REST tipado, WebSocket WAMP, reconexión | MitoCore |
| `MitoStore` | Abrir el snapshot (read-only), DB personal (read-write), settings, migraciones; `DataDragonClient`, el cliente HTTPS que solo habla con `ddragon.leagueoflegends.com` | MitoCore, GRDB |
| `MitoEngine` | Scoring de picks, bans, runas, ítems y spells. **Funciones puras** | MitoCore |
| `MitoAssets` | Íconos de campeones, ítems, runas y spells con caché en disco; sin red propia (el cliente vía LCUKit, Data Dragon vía `DataDragonTransport`, que la app satisface con el `DataDragonClient` de MitoStore) | MitoCore, LCUKit |
| `MitoImport` | Importador: aplica runas, spells e item sets en el cliente (`LoadoutImporter`) | MitoCore, LCUKit |
| App target | Features, vistas, `AppModel`, orquestación | todos |

`MitoEngine` no sabe nada de red ni de UI: recibe un `DraftContext` y un `StatsProvider`
(protocolo) y devuelve recomendaciones con su explicación. Eso permite testearlo con datos
fijos.

`StatsProvider` (MitoCore) es síncrono, `Sendable` y no lanza errores: un dato que falta es
`nil` o vacío. Devuelve **conteos crudos** del snapshot (§17), nunca tasas; las tasas, el
suavizado y los tiers los calcula `MitoEngine` con `meta`. `MitoStore` lo implementa sobre el
snapshot y los tests usan `InMemoryStatsProvider`. Superficie actual:

- `roleGames(for:)`: `champion_roles`, para la inferencia de roles (§12.3).
- `meta`: identidad (`patch`, `queue`, `bracket`), `matches`, `blend_patches`, `thresholds`,
  `priors`, `tier_cutoffs` y `profile_rules` (`ProfileRules`: `min_champions` y los tres
  umbrales, mínimos inclusivos; `mixed` es "ninguno de `mixed.not`"). `nil` si el archivo no
  lo trae. `blend_k` y `regions` no se leen.
- `championRoleStats(in:)`: `games`, `wins` y las sumas `kills`, `deaths`, `assists`, `cs` y
  `minutes` de `champ_role_stats` por campeón en un rol (para §19.2), más
  `champion_profiles.tl_games` como denominador de timeline.
- `runePages`, `spellPairs`, `itemBuilds` y `skillOrders(for:role:)`: candidatos generales
  (`opp_id = 0`) con `games` y `wins`. Las páginas ya vienen resueltas desde `rune_page_defs`.
- Fase 7, por (campeón, rol), cada una una consulta puntual que devuelve `nil` o vacío:
  `matchup(against:)` (`matchup_stats` con `tl_games` y los diffs a los 15, `nil` sin
  timeline), `synergy(with:allyRole:)`, `versusTeam(against:)` y
  `profileStats(against: EnemyProfile)` (`games` y `wins` como `RelationStats`),
  `championProfile` (todas las columnas de `champion_profiles`), `runePages`, `spellPairs` e
  `itemBuilds(against: ChampionID)` (filas con ese `opp_id`), `runePages(against: EnemyProfile)`
  (`rune_page_vs_profile`) y `finalItems` (`item_vs_profile`: sin perfil es la línea base
  `'any'`, con perfil es ese perfil).
- Por campeón: `bans(of:)` (`champ_ban_stats`) y `flags(of:)` (`champion_flags`).
- `durationCurves(for:role:)`: `duration_curves` como `[DurationBucket: RelationStats]`; cada
  `DurationBucket` lleva su etiqueta de §17 (`<20` … `40+`) y sus límites en minutos
  (`[lowerMinutes, upperMinutes)`, `40+` sin techo). Un bucket fuera de la codificación es una
  tabla malformada.
- Por ítem: `itemClass(of:)` (`item_classes.class` como `ItemClass`, tolerante) e
  `isAntiheal(_:)` (`item_classes.antiheal`). Un ítem sin fila es `nil` y no es antiheal.
- `champions` no se lee: `changed` solo lo usa la mezcla del exporter (§14.13), ninguna regla
  del motor.
- `EnemyProfile` y `ChampionFlag` son tolerantes: un valor desconocido carga como `.unknown`.

Todo método tiene una implementación vacía por defecto en la extensión del protocolo, así un
provider que no conoce una tabla compila igual.

La explicación vive en MitoCore porque la produce `MitoEngine` y la dibuja la app: `Reason`
lleva el tipo (`Reason.Kind`, con los números de §18.3–§18.8 y §19.3: deltas y shares como
fracciones, partidas) y su `SampleLevel`; nunca texto. `PickRecommendation` y
`BanRecommendation` llevan candidato, score, componentes por término (§18.3) o factor
(§18.5), razones por impacto y la confianza (el `SampleLevel` de `champ_role`).

`PersonalStore` (MitoCore) es el contrato de la base personal (§17, "Base personal"): async,
`Sendable`, y lanza `PersonalStoreError` (`readFailed`, `writeFailed`). `MitoStore` lo
implementa con GRDB y los tests usan `InMemoryPersonalStore` (MitoTestSupport). Superficie:

- `record(_:)`: upsert de partidas por `game_id`, reemplazando sus participantes.
- `matches(_:)`: partidas por campeón, rol y parche opcionales, de la más nueva a la más
  vieja, con un `limit` de las más recientes (§19.2, §19.4).
- `pool(for:)` y `setPool(_:for:)`: el pool de un rol; el orden de la lista es la prioridad.
- `overrides()`, `save(_:)` y `deleteOverride(champion:role:)`: overrides por (campeón, rol)
  (§21.5). Los modos guardan `adaptive`/`general`/`fixed`, `recommended`/`fixed` y
  `recommended`/`fixed_set`/`skip`; un valor desconocido se conserva como `.unknown`.
- `appendImportLog(_:)` e `importLog(limit:)`: el log de importación, lo más nuevo primero.
- `deleteAll()`: "Borrar mis datos" (§25).

### 9.3 AppModel (orquestador)

```swift
@Observable  // MainActor por default en el target de la app (ADR 0001)
final class AppModel {
    let connection: ConnectionModel
    let clientData: ClientDataModel
    let snapshots: SnapshotModel
    let mainWindow: MainWindowModel
    let gameflow: GameflowModel
    let champSelect: ChampSelectModel
    let importing: ImportModel
    let champions: ChampionsModel
    let analysis: AnalysisModel
    let profile: ProfileModel
    let onboarding: OnboardingModel
    let overrides: OverridesModel
    let settingsModel: SettingsModel
    let personal: any PersonalStore
    var settings: MitoSettings { get set }  // reenvía a settingsModel.value

    init(
        connection: any LCUConnection,
        lifecycle: @escaping @Sendable () async -> Void = {},
        settings: SettingsModel = SettingsModel(),
        snapshots: SnapshotModel = SnapshotModel(),
        personal: any PersonalStore = UnavailablePersonalStore(),
        poster: any NotificationPosting = SystemNotificationPoster(),
        appIsActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }
    )

    var menuBarSymbol: String { gameflow.menuBarSymbol ?? connection.menuBarSymbol }

    func start() async {
        await settingsModel.load()
        await withDiscardingTaskGroup { group in
            group.addTask { await self.lifecycle() }
            group.addTask { await self.connection.run() }
            group.addTask { await self.clientData.run() }
            group.addTask { await self.gameflow.run() }
            // … un addTask por slot
        }
    }
}
```

- **Un slot por feature** (ADR 0007): cada modelo es un `@Observable` en
  `Features/<Nombre>/`, con su `run()`. El shell se escribe una vez; una unidad de feature
  solo toca su carpeta.
- **Sin loop central de eventos**: cada modelo se suscribe a sus propios tópicos con
  `connection.events(_:)` (un stream por suscriptor) y al estado con `connection.states()`.
  No hay `switch` de eventos en `AppModel`.
- **Conexión inyectada** como `any LCUConnection`: el `LCUClient` real en la app, un fake en
  los tests. `DisconnectedLCUConnection` (siempre `.searching`, `send` tira `.notConnected`)
  queda solo para las previews.
- **Ciclo de vida inyectado** como `lifecycle`: `MitoApp` crea el cliente con
  `AppModel.liveClient()` (ruta de instalación por defecto, §10.1, o el override de Debug de
  abajo) y pasa `AppModel.lifecycle(running:underTest:)`, que corre `client.run()` salvo bajo
  XCTest, donde termina al instante y nada se conecta. `start()` lo corre en el mismo task group
  que los slots, así que vive lo que vive `start()` y cancelarlo desarma la conexión (§10.2). En
  tests y previews el default `{}` termina al instante.
- **Notificaciones inyectadas:** `poster` (§22.5) y `appIsActive` (si Mito está en primer
  plano) van a `GameflowModel` e `ImportModel`; los dos comparten un solo poster. Los defaults
  son los reales y `MitoApp` los usa; los tests de `AppModel` pasan un poster que graba, así
  ningún test publica una notificación del sistema.
- Las vistas leen `@Environment(AppModel.self)` y toman el slot que necesitan; los call sites
  del shell no cambian cuando una feature crece.
- **Settings** (§21): `SettingsModel` (en `App/`) tiene el `MitoSettings` vivo. `MitoApp` le
  pasa `SettingsStore()` (ruta por bundle ID); bajo XCTest no le pasa nada, así los tests nunca
  tocan el archivo real, y sin persistencia (previews, tests) no carga ni guarda. `start()`
  carga primero y recién después arranca los slots; hasta entonces se ven los defaults, y un
  cambio hecho antes de que termine la carga se pisa y no se guarda. Cargar no reescribe el
  archivo. Cada cambio posterior de `app.settings` agenda un guardado con debounce de 300 ms
  (gana el último valor) que corre en el actor `SettingsStore`; si falla, `SettingsStore` lo
  loguea sin el contenido y el valor en memoria queda.
- **Lectura desde las features:** `GameflowModel`, `ChampSelectModel` e `ImportModel` reciben en
  su `init` un closure `@MainActor` que devuelve su parte actual (`GameSettings`,
  `ChampSelectSettings`, `ImportSettings`) y lo exponen como `settings()`; no dependen de
  `AppModel`. El default devuelve los defaults, para previews y tests. Las pestañas de
  Settings escriben con bindings a `app.settings` desde `@Environment(AppModel.self)`, y eso
  dispara el guardado.
- **Datos del cliente compartidos:** `ClientDataModel` (en `App/`) tiene el único
  `GameDataCatalog` (§16.1) y, en cada entrada a `connected`, lo recarga y lee
  `LCUEndpoint.gameVersion` una vez. Publica `gameData` (lo último que cargó; una recarga
  fallida lo conserva), `gameVersion` y `patch` (los dos primeros componentes, o `Patch("")`
  mientras la versión no se pudo leer en esta conexión). `ImportModel` recibe el catálogo en su
  `init`; `ChampSelectModel` recibe lectores de `gameData` y `patch`, que lee en vivo;
  `ChampionsModel` y `OnboardingModel` (la lista de campeones del pool, de
  `GameData.allChampions`) reciben un lector de `gameData`, y Overrides lo lee desde la vista.
  Así cada archivo de datos estáticos se pide una vez por conexión, no una por feature.
- **Base personal y Flash detectado:** `AppModel` le pasa `personal` a Profile, Onboarding,
  Overrides e `ImportModel` (overrides e `import_log`, §13.1). A `ImportModel` le inyecta
  además `detectedFlash`, un lector de `onboarding.resolvedFlashSlot(.auto)` traducido a
  `ImportSettings.FlashPosition` (`d`/`f`, o `nil` sin mayoría). La detección no depende de
  abrir la pestaña General: `OnboardingModel.run()` la corre al arrancar, y `ProfileModel`
  recibe `personal` envuelto en `HistoryNotifyingStore` (en `App/`), que después de cada
  `record(_:)` exitoso (cada sync del historial) llama a `onboarding.detectFlash()`. Así el
  shell se entera del sync sin tocar `ProfileModel`. Ninguna feature
  arma hoy un `IconRequest`; cuando lo haga, `gameVersion.rawValue` es su `gameVersion`.
- **Ventana principal:** `MainWindowModel` (en `App/`) tiene la selección del sidebar y decide
  cuándo champ select abre la ventana (§20.1). La etiqueta de la barra de menú
  (`MenuBarLabel`) es la única vista que vive siempre, con o sin ventana abierta: en cada cambio
  de `champSelectPresence` (draft presente y fase de gameflow) pregunta
  `shouldOpenWindowForChampSelect()` y, si da `true`, llama a
  `openWindow(id: MitoApp.mainWindowID)`.
- **Snapshot compartido:** `SnapshotModel` (en `App/`) tiene el `StatsProvider` abierto (un
  `SnapshotReader`, §17), su `meta` y un `status`: `none`, `downloading`, `ready` o
  `failed(.download(SnapshotDownloadError) | .unreadable(SnapshotReadError))`; el status es
  el del último intento, el provider es el último que abrió. Su `run()` abre primero el archivo
  ya instalado (`SnapshotDownloader.installedSnapshot`, solo disco) y después intenta
  `installCurrent` para la cola 420 y el bracket `emerald_plus` (Diamond+ llega después); si
  la descarga sale bien abre el archivo nuevo y lo reemplaza, si falla queda el anterior. La
  falla es silenciosa: se loguea el tipo de error (categoría `App`), `status` queda en `failed`
  y no hay alerta; hoy pasa siempre, porque la URL base es el placeholder `.invalid` (§14.12).
  `SnapshotReader(fileURL:)` lee todo el archivo de forma síncrona, así que abre en una
  función `@concurrent`, fuera del main actor. `ChampionsModel` e `ImportModel` reciben
  `stats: { snapshots.provider }`: el closure lee estado observable, así que la pestaña
  Campeones se actualiza sola cuando abre un snapshot. La fuente es `SnapshotModel.Origin`:
  `MitoApp` usa `.live(underTest:)`, que bajo XCTest da `.none` (no abre nada, no descarga, no
  toca el caché real) y en la app da el caché + la descarga.
- **Base personal compartida:** `AppModel.personal` es el único `PersonalStore` (§17, "Base
  personal"); las features que leen o escriben datos personales lo reciben en su `init`
  (hoy `ProfileModel`). `MitoApp` pasa `UnavailablePersonalStore.live(underTest:)`: en la app
  da `PersonalDatabase()` (ruta por bundle ID, se abre en el primer uso) y bajo XCTest da
  `UnavailablePersonalStore`, que no toca ningún archivo y falla cada llamada. Es también el
  default de `AppModel`, para previews y tests.
- En Debug, `-MitoSnapshotFile <ruta>` (argumento de lanzamiento o UserDefaults) abre ese
  `.sqlite` directamente y no descarga nada; sirve para correr la app sobre
  `fixtures/snapshot/emerald_plus.sqlite` o sobre la salida local de `mito-data`.
- En Debug, `-MitoLCULockfilePath <ruta absoluta>` (argumento de lanzamiento o UserDefaults)
  hace que `AppModel.liveClient()` arme `LCUClient(lockfilePath:)`: el descubrimiento lee solo
  ese lockfile (§10.2), el que escribe `tools/lcu-mock` (§23.1). Release no lee la clave:
  `AppModel.lockfileOverride(in:)` da siempre `nil` y la clave existe solo bajo `#if DEBUG`; un
  test de MitoTests verifica que toda mención de la clave en `Mito/` esté dentro de un
  `#if DEBUG`.

### 9.4 Principios de código

- Swift 6, strict concurrency, sin `@unchecked Sendable` salvo justificado.
- Todo acceso a la LCU pasa por `LCUClient` (actor).
- Los endpoints están tipados: nada de strings sueltos con paths por la app.
- Los modelos `Codable` de la LCU son **tolerantes**: campos opcionales y valores
  desconocidos de enums con un caso `.unknown(String)`. Riot cambia cosas sin avisar.
- Errores tipados (`LCUError`, `StoreError`, `EngineError`) y nunca `fatalError` en runtime.
- Cada feature tiene su `Model` (`@Observable`) + vistas. Nada de lógica en las vistas.

---

## 10. Conexión con el cliente: LCU API

La **LCU (League Client Update) API** es una API REST + WebSocket que expone el cliente de
LoL en localhost. No está documentada oficialmente como producto, pero es la base de todos
los companions. Se usa "tal cual está" y puede cambiar sin aviso.

### 10.1 Descubrimiento

Hay dos métodos. Implementar los dos, con el de proceso como principal. Vive en
`LCUKit/Discovery/`.

**A) Argumentos del proceso (preferido)**

```bash
ps -A -ww -o args=
# .../LeagueClientUx --app-port=54321 --remote-auth-token=AbCdEf123... --app-pid=1234 ...
```

Se parsean `--app-port` y `--remote-auth-token`. Es más confiable porque refleja el proceso
vivo. Solo se leen argumentos: nada de memoria, nada de hooks (§5).

- Candidatos: líneas cuyo ejecutable (lo que va antes del primer `--`) contiene
  `LeagueClientUx`. Así se ignora el Riot Client, que también usa `--app-port` y
  `--remote-auth-token` para su propia API.
- La clave tiene que coincidir exacta: `--riotclient-app-port` y `--riotclient-auth-token`
  (que `LeagueClientUx` también trae) no cuentan.
- Tolerante: cualquier orden, `--clave=valor` o `--clave valor`, comillas simples o dobles
  (también valores con espacios entre comillas, como rutas).
- Puerto entero en 1–65535 y token no vacío; si falta algo, la línea no sirve.
- Con varios candidatos gana el primero completo, en el orden de `ps`.

**B) Lockfile (respaldo)**

- Ruta: `<instalación>/Contents/LoL/lockfile`, con instalación
  `/Applications/League of Legends.app` por defecto o `GeneralSettings.leagueInstallPath`
  (§21.1) si el usuario la configuró.
- Buscar la app cuando no está en `/Applications` (auto-detección) queda pendiente; hoy
  se cubre configurando la ruta.
- Formato: `LeagueClient:<pid>:<port>:<password>:<protocol>`.
- Existe solo mientras el cliente está abierto.
- Tolerante: se ignoran espacios y saltos de línea alrededor, y los campos vacíos no corren
  las posiciones. Con menos de cinco campos el archivo está a medio escribir y no se usa.

```swift
struct LCUDiscovery: Sendable {
    init(
        installPath: String? = nil,
        commandLines: @escaping @Sendable () async -> [String] = runningCommandLines,
        readFile: @escaping @Sendable (URL) async -> String? = contents(of:)
    )
    /// `nil` cuando no hay cliente.
    func discover() async -> LCUCredentials?
}
```

`commandLines` (corre `ps`) y `readFile` son las costuras del sistema: los tests pasan
entradas sintéticas y nunca dependen de un cliente real ni de un lockfile en disco. El parseo
vive en `ProcessArguments` y `Lockfile`. El token nunca se loguea: los logs (`os.Logger`,
categoría `LCUKit`) dicen solo de dónde salió y el puerto, y `LCUCredentials` lo redacta en
toda forma textual.

> Sin verificar contra un cliente real (no hay grabaciones hasta P1-07): el `argv[0]` exacto
> que muestra `ps` en macOS, si los procesos helper de `LeagueClientUx` repiten las
> credenciales, y si el cliente de Mac cita los argumentos como el de Windows.

### 10.2 Polling de descubrimiento

- Cada intento es una llamada a `LCUDiscovery.discover()`: proceso primero, lockfile si el
  proceso no da credenciales, `nil` si no hay cliente. No lanza errores: si `ps` falla se
  loguea y cuenta como "no encontrado". La cadencia y el backoff son del ciclo de vida de la
  conexión.
- **Override de lockfile** (`LCUClient(lockfilePath:)`, para `tools/lcu-mock`): el
  descubrimiento lee **solo** ese archivo y no lista procesos, así un cliente real abierto no le
  gana al mock. Si el archivo no está, el intento da "no encontrado" y la búsqueda sigue con el
  backoff de siempre; verificación, pérdida y TLS (§10.3) no cambian. El mock sirve
  `current-summoner` y borra el lockfile al salir, así que cerrarlo es una pérdida normal. La
  app lo usa solo en Debug (§9.3).
El ciclo de vida es de `LCUClient` (`LCUKit/Connection/`, actor público), que implementa
`LCUConnection` y lo corre `run()` hasta que se cancela la tarea que lo llama:

- **Searching:** el primer intento es inmediato. Mientras no hay cliente se espera entre
  intentos 2 s, 3 s, 4 s y después 5 s fijos; la cuenta vuelve a 2 s cada vez que se pierde un
  cliente.
- **Connecting:** con las credenciales se crea un `LCURESTClient` nuevo y se verifica con
  `GET /lol-summoner/v1/current-summoner`. Cualquier error (404 mientras el cliente termina de
  cargar, conexión rechazada mientras arranca) se reintenta cada 1 s, redescubriendo antes de
  cada reintento: si el cliente ya no está se vuelve a searching; si las credenciales
  cambiaron, se sigue verificando contra las nuevas. Cada intento fallido se loguea en
  `notice` con el caso del `LCUError` y, si es HTTP, el status; nunca el body ni el token.
  Verificado, se abre el WebSocket (§10.5); si no abre, se vuelve a searching.
- **Connected:** el estado pasa a `.connected` y el `LCUEventStream` corre hasta que el socket
  se cierra o falla. `.connected` se publica antes de que se confirme el handshake del
  WebSocket: un handshake fallido aparece como una pérdida.
- **Lost:** el socket terminó (el cliente se cerró o se reinició, y el puerto cambia): se
  suelta el cliente REST, el estado vuelve a `.searching` y se espera 2 s antes de buscar de
  nuevo, así un socket que falla al instante no hace un loop apretado. Mientras está
  conectado no se re-descubre; la pérdida la marca el socket.
- **Cancelación:** cierra el socket, termina los puentes, deja `.searching` y `run()` vuelve.
  Una llamada a `run()` mientras otra sigue corriendo (o desarmándose tras cancelarla) espera
  a que termine y después corre: nunca hay dos ciclos a la vez y ningún arranque se pierde.

Contrato hacia las features (§9.3):

- `send` solo llega al cliente en `.connected`; en cualquier otro estado lanza
  `.notConnected` sin encolar. Un request en vuelo durante el desarme puede fallar con
  `.transport` en vez de `.notConnected`.
- `states()` da a cada suscriptor el estado actual y después cada cambio (sin repetidos).
- Los streams de `events(_:)` y `states()` viven lo que vive su suscriptor, a través de las
  reconexiones: no terminan cuando se cae el cliente. `LCUClient` guarda cada suscriptor y, en
  cada conexión, lo puentea al `LCUEventStream` de turno (un stream interno con los mismos
  topics, reenviado al del suscriptor); un suscriptor que llega con la conexión abierta se
  puentea en ese momento. Los puentes siguen el orden de suscripción. Cancelar el stream del
  suscriptor lo saca del registro, así que la próxima conexión no lo suscribe; en la conexión
  actual su suscripción WAMP se suelta recién con el próximo evento de sus topics o al caer
  la conexión (deuda marcada en el código).
- Logs (`os.Logger`, categoría `LCUKit`): solo las transiciones de estado y el puerto. Nunca
  el token, el PUUID ni nombres.

```swift
public actor LCUClient: LCUConnection {
    public init(installPath: String? = nil)
    public init(lockfilePath: String)
    public func run() async
    public func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R
    public nonisolated func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent>
    public nonisolated func states() -> AsyncStream<ConnectionState>
}
```

Los tests inyectan, por un init interno, el descubrimiento, el cliente REST (seam
`LCURequestSending`), el `WAMPSocket` y el sleep, así recorren el ciclo sin esperar tiempo
real ni tocar la red.

### 10.3 Certificado TLS

La LCU usa HTTPS con un certificado self-signed emitido por la CA de Riot.

- **Opción correcta (pendiente):** embeber el certificado raíz de Riot (`riotgames.pem`,
  conocido en la comunidad) y validar contra él solo para `127.0.0.1`.
- **Opción implementada (mínima):** aceptar el certificado del servidor **solo si el host es
  exactamente `127.0.0.1`** y el challenge es de server trust. Cualquier otro host
  (`localhost`, `::1`, `127.0.0.2`, dominios) u otro tipo de challenge recibe el manejo por
  defecto del sistema.

La decisión es una función pura (`LCUTrust.acceptsServerTrust`, `LCUKit/Client/LCUTrust.swift`)
testeada directamente; el delegate de la sesión solo la aplica:

```swift
enum LCUTrust {
    static func acceptsServerTrust(host: String, authenticationMethod: String) -> Bool {
        host == "127.0.0.1" && authenticationMethod == NSURLAuthenticationMethodServerTrust
    }
}

final class LCUTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        let space = challenge.protectionSpace
        guard LCUTrust.acceptsServerTrust(
                host: space.host, authenticationMethod: space.authenticationMethod),
            let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
```

**Nunca** desactivar la validación TLS de forma global. El fitness test
`ArchitectureTests/NetworkSentinelTests` falla si una fuente de LCUKit arma una URL hacia un
host que no sea `127.0.0.1`, usa `URLSession.shared` (que saltea este delegate), toca
excepciones de validación TLS o sockets crudos, o acepta un server trust fuera de
`LCUTrust.swift`.

### 10.4 REST

`LCURESTClient` (`LCUKit/Client/`, interno al módulo) envía un `LCUEndpoint<Response>` a un
cliente en ejecución y devuelve la respuesta decodificada o un `LCUError`. Se crea con las
`LCUCredentials` de esa instancia del cliente; el `LCUClient` de P1-05 lo compone y crea uno
nuevo cuando cambian las credenciales (por eso no tiene estado mutable ni lanza
`.notConnected`). Recibe un `URLSessionConfiguration` para que los tests inyecten un
`URLProtocol` stub; nunca se testea contra un cliente real ni contra la red.

- **URL:** `https://127.0.0.1:<port><path>`. El `path` debe empezar con `/` (si no, podría
  mover el host, p. ej. `@example.com/…`); si no, o si no forma una URL válida, falla con
  `.encoding` sin enviar nada. El query string del path se conserva.
- **Headers:** `Authorization: Basic base64("riot:<token>")` y `Accept: application/json`;
  `Content-Type: application/json` solo cuando el endpoint lleva body.
- **Errores:** fallo de transporte (conexión rechazada, TLS, cancelación) → `.transport` con
  la descripción localizada del error; status fuera de 2xx → `.http(status:body:)` con el body
  crudo; body que no decodifica → `.decoding`. Los endpoints `LCUNoContent` aceptan un 204
  vacío.
- **Secretos:** el token y el header `Authorization` nunca se loguean ni aparecen en la
  descripción de un `LCUError` (hay un test por cada tipo de error).

```swift
final class LCURESTClient: Sendable {
    init(credentials: LCUCredentials, configuration: URLSessionConfiguration = .ephemeral)
    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R
}
```

Los endpoints se declaran con el contrato `LCUEndpoint` de `LCUKit/Contracts/` (método, path,
body y decoder; `init(method:path:json:)` codifica el body), nunca como paths sueltos en el
llamador.

### 10.5 WebSocket (WAMP)

- URL: `wss://127.0.0.1:<port>/`, con el header `Authorization` y el subprotocolo `wamp`.
- Suscripción a todos los eventos: `[5, "OnJsonApiEvent"]`.
- Suscripción a un recurso puntual: `[5, "OnJsonApiEvent_lol-champ-select_v1_session"]`
  (el path con `/` reemplazado por `_`).
- Mensaje de evento recibido:

```json
[8, "OnJsonApiEvent", {
  "data": { ... },
  "eventType": "Create" | "Update" | "Delete",
  "uri": "/lol-champ-select/v1/session"
}]
```

Framing (WAMP 1.0, `LCUKit/Events/Codec/WAMPCodec`): cada frame es un array JSON cuyo
primer elemento es el opcode. Mito envía `[5, "<topic>"]` para suscribirse y `[6, "<topic>"]`
para desuscribirse, uno por `LCUTopic`. De lo que llega, solo un `[8, "<topic>", {…}]` cuyo
topic es un `LCUTopic` y cuyo objeto trae `uri` y `eventType` como strings se decodifica a
`LCUEvent`; `data` queda como JSON crudo (un `data` ausente o `null` queda como `null`) y cada
feature lo decodifica después. `eventType` desconocido queda como `.unknown`. Todo lo demás
(otros opcodes, el firehose u otros topics, frames que no son array, opcode con otro tipo,
JSON roto) se clasifica como ignorable, sin error que corte el stream. Claves y elementos
extra se toleran. El codec no loguea payloads: pueden traer datos del jugador.

Recomendación: suscribirse a eventos específicos y no al firehose. El firehose manda muchos
eventos irrelevantes y cuesta CPU.

Suscripciones de v1:

| Evento | Para qué |
|---|---|
| `OnJsonApiEvent_lol-gameflow_v1_gameflow-phase` | Fase actual |
| `OnJsonApiEvent_lol-matchmaking_v1_ready-check` | Auto-accept |
| `OnJsonApiEvent_lol-champ-select_v1_session` | Draft en vivo |
| `OnJsonApiEvent_lol-lobby_v2_lobby` | Estado del lobby y roles asignados |
| `OnJsonApiEvent_lol-summoner_v1_current-summoner` | Cambio de cuenta |

Stream (`LCUKit/Events/Stream/`, interno al módulo): `LCUEventStream` abre un socket a
`wss://127.0.0.1:<port>/` con `Authorization: Basic base64("riot:<token>")` y
`Sec-WebSocket-Protocol: wamp`, y reusa el `LCUTrustDelegate` de §10.3 (no hay un segundo
camino de trust). El socket queda detrás de un seam interno (`WAMPSocket`: enviar un frame de
texto, recibir el próximo, cerrar) para que los tests usen un socket en memoria.

- **Un stream por suscriptor:** `events(_ topics:)` devuelve un `AsyncStream<LCUEvent>` propio
  que recibe solo los eventos de esos topics, como pide `LCUConnection.events(_:)`.
- **Suscripciones por conteo:** el socket está suscripto a la unión de los topics en uso. Un
  topic manda `[5, …]` cuando aparece su primer suscriptor y `[6, …]` cuando se va el último;
  dos suscriptores que comparten un topic generan un solo subscribe. Los frames salen por una
  cola FIFO, así que un subscribe y un unsubscribe del mismo topic llegan en orden.
- **Liberación:** cancelar la tarea que itera un stream, o soltar el stream, libera sus topics.
  Después de eso no le llega ningún evento.
- **Buffer `.unbounded`:** `yield` nunca bloquea al lector del socket y no se pierde ningún
  cambio de fase; cinco topics puntuales son poco volumen.
- **Ciclo de vida:** `run()` maneja el socket (lector y escritor) y vuelve cuando el socket se
  cierra o falla, cuando falla un envío, o cuando se cancela la tarea que lo llama. Al volver,
  todos los streams abiertos terminan limpios y la instancia queda gastada: `events(_:)` devuelve
  un stream ya terminado. Reconectar es crear otra instancia; eso lo decide el `LCUClient` de
  P1-05 (§10.2).
- **Privacidad:** no se loguean frames, payloads ni el token.

```swift
final class LCUEventStream: Sendable {
    init(credentials: LCUCredentials, configuration: URLSessionConfiguration = .ephemeral)
        throws(LCUError)
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent>
    func run() async
}
```

### 10.6 Endpoints que usa Mito (v1)

> Los nombres de campos se verifican contra el cliente real con `tools/lcu-recorder` y se
> documentan en `docs/lcu-endpoints.md`. La LCU cambia, así que hay que mantenerlo vivo.

**Sesión y cuenta**

| Método | Path | Uso |
|---|---|---|
| GET | `/lol-summoner/v1/current-summoner` | `LCUEndpoint.currentSummoner` → `CurrentSummoner`: `puuid`, `summonerId`, `gameName`, `tagLine`, `summonerLevel`, todos opcionales; `riotID` da `gameName#tagLine` solo si ambos vienen no vacíos. Campos sin verificar todavía |
| GET | `/lol-patch/v1/game-version` | `LCUEndpoint.gameVersion` → `GameVersion`: el body es un string JSON pelado (`"16.21.723.1234"`); `rawValue` es la versión completa recortada (clave del caché de íconos, solo letras ASCII, dígitos y `._-`) y `patch` son los dos primeros componentes (`16.21`), la misma numeración que `clientPatch` de los fixtures y el snapshot. Un body que no es string, con menos de dos componentes numéricos o con otros caracteres es `LCUError.decoding` |
| GET | `/lol-ranked/v1/current-ranked-stats` | Tier y división por cola (bracket del usuario) |
| GET | `/lol-champion-mastery/v1/local-player/champion-mastery` | `LCUEndpoint.championMastery` → `ChampionMasteryList.masteries: [ChampionMastery]` (MitoCore): campeón, `championPoints` y `championLevel` por entrada; una entrada sin campeón (o con `0`), sin puntos o sin nivel se descarta; un body que no es array es `LCUError.decoding`. La `puuid` del payload nunca se lee. Se lee en vivo, no se guarda (§17). Campos según el schema comunitario, sin verificar todavía |
| GET | `/lol-champions/v1/inventories/{summonerId}/champions-minimal` | Campeones que tenés |
| GET | `/lol-region-locale/v1/region-locale` | Región y locale (para el ruteo de la Riot API) |

**Gameflow, lobby y matchmaking**

| Método | Path | Uso |
|---|---|---|
| GET | `/lol-gameflow/v1/gameflow-phase` | Fase actual |
| GET | `/lol-gameflow/v1/session` | `LCUEndpoint.gameflowSession` → `GameflowSession`: solo cola (`gameData.queue.id`) y mapa (`gameData.queue.mapId`), ver §11.1 |
| POST | `/lol-lobby/v2/lobby` | Crear lobby `{ "queueId": 420 }` |
| PUT | `/lol-lobby/v2/lobby/members/localMember/position-preferences` | Roles `{ "firstPreference": "MIDDLE", "secondPreference": "TOP" }` |
| POST | `/lol-lobby/v2/lobby/matchmaking/search` | Buscar partida |
| DELETE | `/lol-lobby/v2/lobby/matchmaking/search` | Cancelar búsqueda |
| GET | `/lol-matchmaking/v1/ready-check` | Estado del ready check |
| POST | `/lol-matchmaking/v1/ready-check/accept` | Aceptar |
| POST | `/lol-matchmaking/v1/ready-check/decline` | Rechazar |

**Champ select**

| Método | Path | Uso |
|---|---|---|
| GET | `/lol-champ-select/v1/session` | Estado completo del draft |
| PATCH | `/lol-champ-select/v1/session/actions/{actionId}` | Hover o pick/ban `{ "championId": 103 }` |
| POST | `/lol-champ-select/v1/session/actions/{actionId}/complete` | Lockear la acción |
| PATCH | `/lol-champ-select/v1/session/my-selection` | `{ "spell1Id": 4, "spell2Id": 14 }` |
| GET | `/lol-champ-select/v1/pickable-champion-ids` | `LCUEndpoint.pickableChampionIDs` → `Set<ChampionID>`: campeones que se pueden elegir. El body es un array de ids; los `0` y todo lo que no sea entero se descartan; un body que no es array es `LCUError.decoding` |
| GET | `/lol-champ-select/v1/bannable-champion-ids` | `LCUEndpoint.bannableChampionIDs` → `Set<ChampionID>`: campeones que se pueden banear, con la misma decodificación |

**Runas**

| Método | Path | Uso |
|---|---|---|
| GET | `/lol-perks/v1/pages` | Páginas existentes |
| GET | `/lol-perks/v1/currentpage` | Página activa |
| POST | `/lol-perks/v1/pages` | Crear página |
| PUT | `/lol-perks/v1/pages/{id}` | Editar página |
| DELETE | `/lol-perks/v1/pages/{id}` | Borrar página |
| GET | `/lol-perks/v1/inventory` | Cupo de páginas |
| GET | `/lol-perks/v1/styles` | Árboles de runas |
| GET | `/lol-perks/v1/perks` | Runas individuales |

**Item sets**

| Método | Path | Uso |
|---|---|---|
| GET | `/lol-item-sets/v1/item-sets/{summonerId}/sets` | Sets actuales |
| PUT | `/lol-item-sets/v1/item-sets/{summonerId}/sets` | Reemplazar los sets (enviar todos) |

**Historial propio**

| Método | Path | Uso |
|---|---|---|
| GET | `/lol-match-history/v1/products/lol/current-summoner/matches?begIndex=0&endIndex=20` | `LCUEndpoint.matchHistory(begIndex:endIndex:localPUUID:)` → `MatchHistoryPage.matches: [MyMatch]`, en el orden del cliente; los índices van tal cual en el query (por defecto `0` y `20`). `games.games` es obligatorio (si falta es `LCUError.decoding`); una partida que no se puede mapear se descarta y el resto de la página sigue |
| GET | `/lol-match-history/v1/games/{gameId}` | `LCUEndpoint.matchHistoryGame(_:localPUUID:)` → `MatchHistoryGame.match: MyMatch`, con los diez participantes; si no se puede mapear es `LCUError.decoding` |

Mapeo de una partida a `MyMatch` (§17), con los campos del schema comunitario, sin verificar
todavía contra el cliente real:

- **Identificación.** El jugador local es el `participantId` de la entrada de `participantIdentities` cuya
  `player.puuid` coincide con `localPUUID` (`CurrentSummoner.puuid`), comparada en memoria y
  descartada; si no hay coincidencia, la única identidad presente, que es como la lista del
  historial marca al invocador actual. Sin jugador local la partida se descarta. Nombres,
  Riot IDs e IDs de cuenta nunca se decodifican (§5, §25).
- **Cabecera.** `gameId`, `queueId`, `gameCreation` (epoch ms → `playedAt`), `gameDuration`
  (segundos) y el parche, los dos primeros componentes de `gameVersion` (como
  `GameVersion`). Todos obligatorios.
- **Jugador local.** `championId`, `teamId`, `spell1Id` y `spell2Id` en orden de slot (el
  primero es la D), `stats.win`, `kills`, `deaths`, `assists`, y CS =
  `totalMinionsKilled + neutralMinionsKilled`, todos obligatorios. Runas: `stats.perk0…perk5`
  sin ceros (el payload no trae los fragmentos de stats). Ítems: `stats.item0…item6` en
  orden y después `stats.roleBoundItem` (el slot de la misión de rol, donde casi todo BOTTOM
  tiene las botas), sin slots vacíos; `item6` sigue siendo el trinket. Si `roleBoundItem`
  falta o no es un entero, no suma nada. De ese slot se descartan los ids de misión, que no
  se compran (`1200…1209` y `1220…1222`); todo lo demás se conserva, incluidos `2055`,
  `2422` y `1001`: `items` es el inventario final y los consumidores clasifican después. La
  lista de misiones crece con los parches; filtrar por comprabilidad según `item.json` queda
  para una unidad posterior con datos estáticos.
- **Rol.** De `timeline.lane` y `timeline.role`: `TOP`, `JUNGLE`, `MIDDLE`/`MID`;
  `BOTTOM`/`BOT` con `DUO_CARRY`/`CARRY` es `BOTTOM` y con `DUO_SUPPORT`/`SUPPORT` es
  `UTILITY`; cualquier otro valor es `nil`. Fuera de la Grieta (`mapId` distinto de 11, como
  ARAM) todos los roles son `nil`.
- **Rival.** El único enemigo con el mismo rol que el jugador local; si hay más de uno, ninguno
  o el rol es `nil`, no hay rival.
- **Un solo ganador.** Una partida sin exactamente un equipo ganador (un aborto del servidor,
  `endOfGameResult: Abort_Unexpected`, trae los dos equipos perdidos) no se mapea: se descarta
  de la página y `matchHistoryGame` es `LCUError.decoding`. Decide `teams[].win` (string,
  `"Win"` o `"Fail"`; cualquier otro valor cuenta como sin resultado) cuando da resultado para
  dos equipos o más: tiene que haber exactamente un `"Win"`. Si no, decide `stats.win` de cada
  participante agrupado por `teamId`: se descarta solo si reportan dos equipos o más y ningún
  participante ganó. Sin ninguno de los dos (sin `teams` y solo el `stats` del jugador local)
  la partida se mapea como antes, con su `stats.win`. Las remakes no se tocan acá; las partidas
  cortas se excluyen en los insights (§19.4).
- **Los otros nueve.** Solo campeón, lado (`teamId` distinto del propio) y rol. Un
  participante sin `participantId`, `teamId` o campeón se descarta.

**Assets (servidos por el propio cliente, sin internet)**

| Método | Path | Uso |
|---|---|---|
| GET | `/lol-game-data/assets/v1/champion-summary.json` | Lista de campeones |
| GET | `/lol-game-data/assets/v1/champion-icons/{championId}.png` | Ícono |
| GET | `/lol-game-data/assets/v1/perks.json` | Runas |
| GET | `/lol-game-data/assets/v1/perkstyles.json` | Árboles |
| GET | `/lol-game-data/assets/v1/items.json` | Ítems |
| GET | `/lol-game-data/assets/v1/summoner-spells.json` | Spells |

---

## 11. Flujo de juego (gameflow) y máquina de estados

### 11.1 Fases del cliente

Valores conocidos de `gameflow-phase` (tratar los desconocidos como `.unknown`):

```
None → Lobby → Matchmaking → ReadyCheck → ChampSelect → GameStart → InProgress
     → WaitingForStats → PreEndOfGame → EndOfGame → (Lobby | None)
```

Otros: `Reconnect`, `CheckedIntoTournament`.

`LCUKit/Gameflow/GameflowPhase` modela estos doce valores, con `.unknown(String)` para
cualquier otro (la comparación distingue mayúsculas). Se decodifica del body de
`GET /lol-gameflow/v1/gameflow-phase` (`LCUEndpoint.gameflowPhase`), que es un string JSON
pelado (`"ChampSelect"`), y del `data` de un evento `LCUTopic.gameflowPhase`
(`GameflowPhase(event)`), que trae el mismo string. Un valor desconocido nunca falla; un body
que no es string (`null`, número, objeto) es `LCUError.decoding`. Valores sin verificar todavía
contra una grabación.

**Sesión.** La cola y el mapa salen de `GET /lol-gameflow/v1/session`
(`LCUEndpoint.gameflowSession`), decodificado en `LCUKit/Gameflow/Session/GameflowSession`.
Solo se leen `gameData.queue.id` (`queueID: QueueID?`) y `gameData.queue.mapId`
(`mapID: Int?`, 11 es la Grieta y 12 el Abismo); `queueType` los mapea con
`QueueType(queueID:)`, así que una cola desconocida es `.other(id)`. Si falta `gameData`,
`queue` o alguno de los dos campos, o vienen en `null`, queda `nil`. Un body que no es un
objeto, o un `id`/`mapId` con otro tipo, es `LCUError.decoding`. Los rosters (`teamOne`,
`teamTwo`, `playerChampionSelections`) y cualquier identidad no se decodifican nunca (§5), así
que un roster malformado no afecta la sesión. No hay suscripción WAMP a la sesión: se lee por
REST cuando hace falta la cola. Rutas tomadas del esquema comunitario de la LCU, sin verificar
todavía contra una grabación.

### 11.2 Máquina de estados de Mito

```
            ┌───────────┐  cliente encontrado  ┌────────────┐
            │ Searching │ ───────────────────▶ │ Connecting │
            └───────────┘                      └─────┬──────┘
                  ▲                                  │ OK
                  │ conexión perdida                 ▼
                  │                           ┌────────────┐
                  └────────────────────────── │ Connected  │
                                              └─────┬──────┘
                                                    │ phase
     ┌──────────┬──────────────┬────────────────────┼──────────────┬──────────────┐
     ▼          ▼              ▼                    ▼              ▼              ▼
   Idle      Lobby       Matchmaking          ReadyCheck     ChampSelect     InGame
                                                    │              │
                                         auto-accept│     draft engine +
                                                    ▼     importers
```

`LCUKit/Gameflow/MitoStateMachine` es un reducer puro (struct, sin I/O, timers ni
suscripciones): recibe cada `ConnectionState` y cada `GameflowPhase` con `apply(_:)` y expone
`state: MitoState`. Solo describe el estado; no dispara acciones (el auto-accept es §11.3).

- Sin conexión manda: `searching` y `connecting` se muestran tal cual, sea cual sea la fase.
- Perder la conexión (`searching` o `connecting`) olvida la fase, así que al reconectar no
  se muestra una vieja: se queda en `idle` hasta que llegue la fase nueva.
- Una fase que llega sin estar `connected` se ignora.
- `connected` sin fase todavía es `idle`.

| `GameflowPhase` | `MitoState` |
|---|---|
| `None` | `idle` |
| `Lobby`, `CheckedIntoTournament` | `lobby` |
| `Matchmaking` | `matchmaking` |
| `ReadyCheck` | `readyCheck` |
| `ChampSelect` | `champSelect` |
| `GameStart`, `InProgress`, `Reconnect` | `inGame` |
| `WaitingForStats`, `PreEndOfGame`, `EndOfGame` | `idle` |
| desconocida | `idle` |

`Reconnect` cuenta como partida: hay una en curso a la que volver. El post-game es `idle`
porque la partida terminó y Mito no tiene nada que hacer ahí. `CheckedIntoTournament` (Clash)
es esperar en un lobby. Una fase desconocida cae en `idle`, el estado que no hace nada.

### 11.3 Auto-accept

El auto-accept solo contesta el ready check, antes de la partida: nunca elige, banea ni actúa
dentro de una partida (§5). Con `off` no se manda nada nunca.

- Al llegar `ReadyCheck` con `state == "InProgress"` y `playerResponse == "None"`:
  - Esperar `GameSettings.autoAcceptDelaySeconds` (default 2 s, acotado a 0–8 s), para que
    parezca humano y te dé tiempo de cancelar.
  - Si en ese lapso el usuario respondió desde el cliente (aceptó o rechazó), o el ready check
    terminó o desapareció, no hacer nada.
  - Volver a leer el ready check y los settings; si sigue calificando,
    `POST /lol-matchmaking/v1/ready-check/accept`. Una sola vez por ready check.
- Notificación del sistema, una por ready check: "Partida encontrada, aceptada" si Mito
  aceptó, o "Partida encontrada" si no contesta por los settings (`off`, o una cola no elegida
  o desconocida con `selectedQueues`). Nada si el usuario ya respondió, si el ready check
  terminó o si el accept falló.
- Opciones (`GameSettings.autoAccept`): `always` (aceptar siempre), `selectedQueues` (solo
  las colas de `autoAcceptQueues`) u `off` (solo notificar).

**Modelo.** `LCUKit/Matchmaking/ReadyCheck` se decodifica del body de
`GET /lol-matchmaking/v1/ready-check` (`LCUEndpoint.readyCheck`, 404 si no hay ready check) y
del `data` de un evento `LCUTopic.readyCheck` (`ReadyCheck(event)`). Lee solo `state` y
`playerResponse`, ambos obligatorios (si falta uno es `LCUError.decoding`); el resto de los
campos se ignora. `state`: `InProgress`, `EveryoneReady`, `StrangerNotReady`,
`PartyNotReady`, `Invalid`, `Error`; `playerResponse`: `None`, `Accepted`, `Declined`. Ambos
tienen `.unknown(String)` y distinguen mayúsculas. Un evento `Delete`, o con `data` `null` o
vacío, es `nil`: el ready check ya no existe. Aceptar es `LCUEndpoint.acceptReadyCheck`, un
POST sin body que responde `LCUNoContent`. Valores sin verificar todavía contra una grabación.

**Política.** `AutoAcceptPolicy.decide(settings:queue:readyCheck:)` es pura y devuelve
`.accept(after:)` o `.skip(razón)`. Mira primero el ready check y después los settings:

| Condición | Decisión |
|---|---|
| `state != InProgress` | `skip(.notInProgress(state))` |
| `playerResponse != None` | `skip(.alreadyAnswered(respuesta))` |
| `off` | `skip(.disabled)` |
| `selectedQueues` sin cola conocida | `skip(.unknownQueue)` (nunca adivina) |
| `selectedQueues` con una cola no elegida | `skip(.queueNotSelected(cola))` |
| `always`, o `selectedQueues` con la cola elegida | `accept(after: delay)` |

**Ejecución.** `AutoAccepter(connection:clock:)` con `run(context:report:)` escucha
`LCUTopic.readyCheck` de una conexión hasta que el stream termina (o la tarea se cancela).
`context` da los `GameSettings` y la cola actual (`QueueID?`) y se lee en cada decisión, así
que apagarlo durante el delay cancela el accept. El reloj se inyecta (default
`ContinuousClock`).

- Un ready check no trae id: es una racha de observaciones `InProgress`. Termina cuando llega
  un estado distinto de `InProgress` o un `Delete`; lo siguiente que llegue es uno nuevo.
- Se decide una vez por ready check. Si la política dice `skip`, se reporta y no se espera.
- Durante el delay, una observación que lo descarta (respuesta del usuario, fin del ready
  check) retira el accept y reporta el motivo. Un evento ilegible se ignora: lo cubre la
  relectura.
- Después del delay relee el ready check (404 es `.readyCheckEnded`) y los settings, y vuelve a
  aplicar la política. Recién ahí manda el POST; desde ese momento nada lo retira.
- Un POST fallido se reporta y no se reintenta.
- Cada decisión produce un `AutoAcceptReport`: `.accepted`, `.skipped(razón)` o
  `.failed(LCUError)`. La notificación sale de ese reporte (P2-04), no del accepter.

**En la app.** `GameflowModel` le da al accepter un solo stream de ready checks: los eventos en
vivo y, al conectar, una lectura REST (el stream solo trae cambios, y un ready check ya
abierto no se vería). Cada evento en vivo, y el fin sintético de un ready check al perder la
conexión, sube una generación; la lectura solo se reenvía si la generación no cambió desde que
se pidió. Si vuelve después de que el stream mostró y terminó ese mismo ready check, se
descarta: reenviarla abriría una racha nueva y una segunda notificación. El stream termina
cuando terminaron los streams de la conexión y las lecturas pendientes.

---

## 12. Champ select en detalle

### 12.1 Estructura relevante de la sesión

Campos que usa Mito de `GET /lol-champ-select/v1/session` (verificar con el recorder):

```json
{
  "localPlayerCellId": 2,
  "myTeam": [
    {
      "cellId": 2,
      "championId": 0,
      "championPickIntent": 103,
      "assignedPosition": "middle",
      "spell1Id": 4,
      "spell2Id": 14,
      "puuid": "...",
      "team": 1
    }
  ],
  "theirTeam": [ { "cellId": 7, "championId": 238, "assignedPosition": "" } ],
  "actions": [
    [ { "id": 1, "actorCellId": 0, "championId": 0, "type": "ban",
        "isInProgress": true, "completed": false, "isAllyAction": true } ],
    [ { "id": 11, "actorCellId": 2, "type": "pick", "isInProgress": false, "completed": false } ]
  ],
  "bans": { "myTeamBans": [], "theirTeamBans": [] },
  "timer": { "phase": "BAN_PICK", "adjustedTimeLeftInPhase": 27000 }
}
```

Notas:

- `assignedPosition` viene en minúscula (`top`, `jungle`, `middle`, `bottom`, `utility`) en
  colas con roles. En blind pick viene vacío.
- El rol de los rivales **no viene**. Hay que inferirlo (ver 12.3).
- `championPickIntent` es el hover. Sirve para recomendar antes de que el aliado lockee.
- `timer.phase`: `PLANNING`, `BAN_PICK`, `FINALIZATION`.

**Modelo en LCUKit.** `LCUEndpoint.champSelectSession` (GET, 404 fuera de champ select)
decodifica `ChampSelectSession`; `ChampSelectSession(_ event:)` decodifica el `data` del
evento `LCUTopic.champSelectSession` con el mismo decoder. Los nombres de campos de arriba
**todavía no están verificados** contra una grabación (`docs/lcu-endpoints.md`). Reglas de
tolerancia:

- Todo campo escalar es opcional; `myTeam`, `theirTeam`, `actions` y los arrays de `bans`
  valen `[]` si faltan, son `null` o no son un array. Las claves desconocidas se ignoran.
- `championId`, `championPickIntent`, `spell1Id` y `spell2Id` en `0` se decodifican como
  `nil` (sin campeón o sin spell). Los `0` de `bans` se descartan.
- `assignedPosition` es `.role(Role)` para los valores en minúscula, `.unassigned` si viene
  vacío o falta, y `.unknown(String)` para cualquier otro valor.
- `type` de una acción (`ban`, `pick`, `ten_bans_reveal`) y `timer.phase` tienen
  `.unknown(String)` para valores nuevos.
- **Un elemento malformado se descarta**, no se decodifica como desconocido: un miembro, una
  acción, un grupo de acciones o un ban que no es un objeto (o un número) o trae un campo con
  tipo inesperado se saltea, y el resto de la sesión sigue. Se eligió descartar porque un
  elemento así no aporta datos confiables; un campo que solo falta no lo invalida.
- `timer.adjustedTimeLeftInPhase` (ms) acepta decimales y se redondea; si viene con otro tipo
  queda `nil` sin tumbar la sesión.
- **No se modela ninguna identidad** (`puuid`, `summonerId`, nombres), ni propia ni ajena
  (§5). La sesión nunca se loguea.

### 12.2 Modelo de dominio

```swift
struct DraftContext: Sendable {
    let queue: QueueType                 // ranked solo, flex, normal draft, ARAM...
    let patch: Patch
    let myRole: Role?                    // nil en blind / ARAM
    let myCellId: Int
    let allies: [DraftSlot]              // incluye al jugador local
    let enemies: [DraftSlot]
    let bans: Set<ChampionID>
    let pickable: Set<ChampionID>
    let phase: DraftPhase
    let isMyTurnToPick: Bool
    let isMyTurnToBan: Bool
}

struct DraftSlot: Sendable {
    let cellId: Int
    let champion: ChampionID?            // lockeado
    let hover: ChampionID?               // intent
    let role: Role?                      // asignado (aliados) o inferido (rivales)
    let roleConfidence: Double           // 1.0 asignado; <1 inferido
}
```

**Mapeo desde la sesión.** `ChampSelectSession.draftContext(queue:patch:pickable:)` en LCUKit
es una función pura. `queue`, `patch` y `pickable` no vienen en la sesión: se pasan desde
afuera (sesión de gameflow, parche activo y `pickable-champion-ids`). El resto sale de la
sesión:

- `myCellId` es `localPlayerCellId`; `myRole` es el `assignedPosition` del miembro de
  `myTeam` con esa celda (`nil` en blind, ARAM o con un valor desconocido).
- `allies` es `myTeam` (incluye al jugador local) y `enemies` es `theirTeam`, en el orden de
  la sesión. Un miembro sin `cellId` se descarta.
- **Lock y hover van por separado.** Durante su propio turno, el cliente pone en el
  `championId` del miembro el campeón que está hovereando, antes de lockear. Por eso un
  campeón cuenta como lockeado solo si hay una acción `pick` con `completed` en `true` para
  esa celda; el campeón sale de esa acción, o del `championId` del miembro si la acción no
  trae uno. Aliados y rivales se tratan igual.
- **Fallback sin acciones visibles:** si una celda no tiene ninguna acción `pick` (acciones
  ocultas, colas sin acciones de pick por celda), su `championId` se toma como lockeado.
- El hover es el `championId` del miembro mientras no esté lockeado y, si no hay, su
  `championPickIntent`. Si vienen los dos, gana `championId`: es el hover actual del turno y
  el intent es la intención previa al turno.
- El rol de un slot es el `assignedPosition` del cliente con confianza 1.0; sin posición,
  `role` es `nil` y `roleConfidence` 0. Los rivales quedan así: LCUKit no importa MitoEngine,
  y la inferencia de 12.3 completa sus roles después.
- `bans` es la unión de `myTeamBans`, `theirTeamBans` y el campeón de cada acción `ban`
  completada. El hover de un ban en curso no cuenta.
- `phase` sale de `timer.phase`. `isMyTurnToPick` e `isMyTurnToBan` son verdaderos cuando hay
  una acción de ese tipo con `isInProgress` en `true`, `completed` distinto de `true` y
  `actorCellId` igual a `myCellId`.
- Devuelve `nil`, porque no hay contexto útil, cuando falta `localPlayerCellId`, cuando ningún
  miembro de `myTeam` tiene esa celda, o cuando `timer` o `timer.phase` faltan o la fase es
  desconocida.
- Solo usa campeones, celdas y roles (§5). No loguea nada.

### 12.3 Inferencia de roles rivales

Los rivales no traen rol. Se infieren con las distribuciones de rol del snapshot
(`RoleInference.infer(enemies:takenRoles:stats:)` en `MitoEngine`, función pura):

1. Para cada campeón rival lockeado se tiene `P(role | champion)` desde `champion_roles`
   (`games` del rol / suma de `games` del campeón, vía `StatsProvider.roleGames(for:)`).
2. Se busca la **asignación 1 a 1** de campeones a roles que maximiza el producto de
   probabilidades (con 5 campeones son 120 permutaciones, trivial por fuerza bruta).
3. Con menos de 5 lockeados se hace lo mismo con los roles libres: los que no están en
   `takenRoles` (roles que ya se sabe que están ocupados).
4. Por campeón se guarda `roleConfidence` = masa de probabilidad de las asignaciones que le dan
   ese rol / masa de todas las asignaciones válidas. También se expone `roleProbabilities`: la
   probabilidad marginal de cada rol libre para ese campeón, sobre todas las asignaciones.
5. Si la confianza del oponente de lane es baja, el motor mezcla matchups ponderando por
   probabilidad (por ejemplo, 70 % vs Zed mid y 30 % vs Zed top), usando `roleProbabilities`.
6. Campeón sin filas en `champion_roles` (nuevo o sin datos en el parche), o con 0 partidas en
   todos los roles libres: distribución uniforme sobre los roles libres, marcado con
   `isUniformFallback` (confianza baja aunque `roleConfidence` salga alta por descarte). Sin
   datos de matchup contra él, el motor cae al perfil rival, y si tampoco tiene
   `champion_profiles` no cuenta para el perfil.

Casos borde, todos deterministas:

- **Empates**: gana la primera asignación en orden de enumeración — campeones en el orden de
  entrada, y cada uno prueba los roles en el orden de declaración de `Role` (top, jungle,
  middle, bottom, utility). Con dos campeones idénticos, el primero se queda con el rol que
  aparece antes.
- **Cero campeones**: resultado vacío.
- **Más rivales que roles libres**: los que sobran quedan sin rol (`role == nil`,
  `roleConfidence == 0`). Un campeón sin rol aporta factor 1 al producto, así que quedan
  afuera los de peor encaje; en empate, quedan afuera los últimos.
- **Todas las asignaciones con probabilidad 0** (por ejemplo, dos campeones que solo juegan
  bottom con un solo bottom libre): se repite la búsqueda con conteos suavizados
  (`games + 1` por rol, sobre los 5 roles).
- **Campeón duplicado**: no puede pasar en un draft; no se trata como caso especial.

### 12.4 Cuándo recalcular

- Cada `Update` de la sesión dispara un recálculo (con debounce de 150 ms).
- El cálculo tiene que tardar **menos de 50 ms**: todo en memoria, con índices cargados al
  entrar en champ select.
- La UI muestra resultados parciales en cuanto los tiene.

**`ChampSelectModel`** (feature `ChampSelect`) sigue la sesión y publica el `DraftContext`:

- Se suscribe a `LCUTopic.champSelectSession`. Cada evento reinicia un debounce de 150 ms
  (`ChampSelectModel.debounce`, con el reloj inyectado); al vencer se mapea la última sesión
  recibida. Una ráfaga de eventos produce una sola actualización.
- Los eventos solo traen cambios, así que al entrar en `connected` (al arrancar y en cada
  reconexión) lee la sesión una vez con `LCUEndpoint.champSelectSession`, sin debounce. Un 404
  (fuera de champ select) borra el draft.
- Un evento `Delete`, una sesión que no se puede decodificar o salir de `connected` borran el
  draft al instante y cancelan la actualización pendiente. Gana siempre la última escritura:
  una lectura o un mapeo que termina después de algo más nuevo se descarta.
- Con la primera sesión de cada champ select pide una vez, en paralelo, la cola
  (`gameflowSession`) y `pickableChampionIDs`, y los reusa hasta que se borra el draft. Si la
  cola no se puede leer queda `QueueType.other(0)`; si falla `pickable`, queda vacío.
- **Parche:** el `DraftContext` lleva el parche del cliente (`.gameVersion`, §10.6) que lee el
  shell una vez por conexión (`ClientDataModel`, §9.3); vale `Patch("")` mientras no se pudo
  leer.
- Mapea con `draftContext(queue:patch:pickable:)` (§12.2); si devuelve `nil`, no hay draft y la
  vista no muestra nada.
- Los roles de los rivales lockeados sin posición se infieren con `RoleInference` (§12.3) solo
  para mostrar, con el `StatsProvider` del snapshot abierto (`SnapshotModel.provider`).
  `enemyRoles` se deriva al leerse, así que un snapshot que abre a mitad del draft se aplica al
  instante. Sin snapshot (o un campeón sin filas en `champion_roles`) sale `isUniformFallback`
  y la UI lo marca como incierto.
- **Blind pick:** sin rol asignado (y fuera de ARAM) el modelo elige un rol para puntuar
  (`scoringRole`, §20.3). La elección manual (`chooseRole`) vale hasta que se borra el draft.
- Además publica las celdas con un ban o pick en curso y el intervalo del timer de la fase
  (`adjustedTimeLeftInPhase` contado desde que llega la sesión). Los nombres de campeones salen
  del `GameDataCatalog` compartido del shell (`ClientDataModel`, §9.3), recargado en cada
  conexión; sin datos se muestra "Campeón <id>". No loguea la sesión.

### 12.5 Auto-hover, auto-pick y auto-ban (opcionales)

- **Auto-hover** (default: off): al empezar el turno de pick, hacer hover del pick #1
  recomendado de tu pool (`PATCH` de la action sin `complete`). Bajo riesgo y útil.
- **Auto-ban** (default: off): banear el #1 de la lista de bans configurada, o el
  recomendado. Respetar el hover de los aliados: **nunca** banear lo que un aliado tiene en
  hover.
- **Auto-pick/lock** (default: off, con advertencia): lockear el pick preferido si está
  disponible. Lista de prioridad configurada por rol.
- Todas con confirmación explícita la primera vez que se activan.

---

## 13. Importación de runas, spells e ítems

### 13.1 Cuándo se importa

- Trigger principal: **cuando tu campeón queda lockeado**.
- Trigger opcional: al hacer hover (`importOnHover`, apagado por defecto). Importa una versión
  preliminar y la actualiza al lockear.
- Re-import automático si cambia el contexto relevante: se revela el oponente de lane o la
  composición rival cambia los situacionales. Solo si el usuario no tocó la página a mano
  (se detecta comparando la página actual con la que puso Mito).

**Implementado hoy (Fase 4, `Features/Import/ImportModel`).** El modelo sigue los eventos de
`LCUTopic.champSelectSession` y decide con el mismo mapeo de §12.2
(`ChampSelectSession.draftContext`): el slot del jugador local cuenta como lockeado solo con
una acción `pick` completada (o sin acciones de pick para su celda); su hover cuenta solo con
`importOnHover`. Cada campeón se importa **una vez por champ select**: un hover que ya importó
no se repite al lockear; después solo se re-importa lo que cambie el contexto (abajo). Un
evento `Delete` de la sesión
(fin del champ select) o una desconexión lo resetea, junto con cualquier confirmación
pendiente. Una sesión que no se puede decodificar se ignora.

- **Contexto** (`LoadoutImportContext`): título `<Campeón> <ROL>` (`Ahri MID`; el rol corto es
  TOP, JGL, MID, ADC o SUP y es el rol de la build importada), con el nombre del campeón de
  `GameDataCatalog` en el locale del cliente o, si no cargó, su ID numérico. El mapa
  sale de `mapID` de `GET /lol-gameflow/v1/session`: `11` es Summoner's Rift; cualquier otro
  mapa (o una sesión ilegible) no tiene código conocido, así que el item set **no se envía**
  y el toast lo dice. Igual si `CurrentSummoner` no trae `summonerId`. Runas y spells siguen.
- **Loadout del snapshot (P6-06).** `ImportModel` recibe en su `init` un lector
  `stats: @MainActor () -> any StatsProvider` (el de `SnapshotModel`, §9.3) y elige con
  `LoadoutSelection.general(for:role:stats:)` (§18.6–§18.9) la build general (`opp_id = 0`)
  de (campeón, rol). El rol es el `assignedPosition` del jugador local; en blind pick o sin rol
  es el rol con más `roleGames` de ese campeón en el snapshot (empate: el primero en
  `Role.allCases`), y si no tiene ninguno no se importa nada ni se avisa. Tampoco se avisa si
  el campeón no tiene datos en ese rol (las tres partes vacías). Los bloques del item set
  llegan titulados con el `BuildLayer` (o `situational`) y la app los traduce (§13.4) antes de
  dárselos a `LoadoutImporter`. El skill order no se importa (el cliente no tiene API).
- **Loadout adaptado (P7-10).** Con el mismo rol, `ImportModel` arma también
  `LoadoutSelection.adapted(for:role:opponent:enemyProfile:enemies:stats:)` (§18.6–§18.8) con
  la sesión que ya tiene, y esa es la build que se importa por defecto:
  - **Rival de lane** (`ImportModel.laneOpponent`): el rival lockeado con ese rol asignado; si
    no hay, entre los rivales lockeados sin rol, el de mayor `roleProbabilities[rol]` de
    `RoleInference` (§12.3, con los roles asignados de rivales como ocupados), solo si esa
    probabilidad es **≥ 0,5** (`minimumLaneOdds`). Debajo de 0,5 la adivinanza es una moneda al
    aire: se pasa `nil` y la build se adapta solo al perfil (no se mezclan matchups ponderados
    como en el score de pick). Un rol ocupado por un rival que todavía no lockeó no tiene rival.
    En el fixture, Zed solo (44 % MIDDLE) no cuenta; Zed con Lee Sin (solo JUNGLE) sí.
  - **Perfil rival**: `Composition.enemyProfile(in:stats:)` (§18.4) sobre la sesión.
  - **Rivales**: los campeones rivales lockeados, para los flags de §18.7.
  - El rival también va en la notificación (`.loadoutImported(champion:opponent:)`); el título
    de la página y del set sigue siendo `Ahri MID`, sin "vs Zed".
  - **Toast.** Cada fila cuya parte salió adaptada suma un marcador corto en una sola fila:
    "· vs Zed" (`adaptedToOpponent`), "· vs mucho AD" (`adaptedToProfile`; también mucho AP,
    mucho CC y daño mixto), y en ítems además cada flag ("· Morellonomicon: 2 rivales con
    curación alta") y cada situacional ("· Zhonya vs mucho AD"), sin repetidos y en el orden de
    `Loadout.explanation`. Los nombres salen de `GameDataCatalog` (o el ID sin catálogo). Como
    "· muestra baja", solo si la recomendación quedó en el cliente o espera confirmación; una
    parte que salió del override o de la general no lleva marcador. "· muestra baja" usa el
    `SampleLevel` de la build que se mandó en esa parte (general o adaptada).
- **Muestra baja.** `GeneralLoadout.sampleLevels` da un `SampleLevel` por parte (para los
  ítems, el bloque más débil); cada fila del toast cuya parte quedó por debajo de `reliable`
  (§18.2) suma "· muestra baja", solo si la recomendación quedó en el cliente o espera
  confirmación (aplicada, ya elegida o `needsConfirmation`), no si la parte se salteó o falló.
- **Sin snapshot** (§20.3): no se importa nada, no se manda nada al cliente, y se avisa **una
  vez por champ select** con el título "Sin estadísticas del parche: no se importó nada para
  Ahri MID", sin filas.
- **Overrides por campeón (P8-09, §21.5).** Antes de armar el loadout, `ImportModel` lee el
  `ChampionOverride` de (campeón, rol) con `PersonalStore.overrides()`, con el mismo rol que ya
  resolvió (asignado, o el más jugado en blind). Si la base no se puede leer, se importa como
  sin override. `ImportModel.plan(_:override:settings:)` aplica, en este orden:
  - **Los toggles globales ganan.** Con `importRunes`, `importSpells` o `importItemSets`
    apagado, esa parte queda como estaba y el importador la saltea (`disabled`), diga lo que
    diga el override.
  - **Runas.** `.fixed` manda `fixedPage` por el importador de siempre, que la valida contra
    los estilos del cliente (§13.2): si ya no es válida no se envía, no se cae a la general, y
    la fila dice por qué ("Página inválida (una rama ya no existe), no se envió"). `.general`
    manda la página **general** del motor (`opp_id = 0`, nunca la adaptada), diga lo que diga
    el modo global. `.adaptive` (el default del editor, "sin preferencia"), `.unknown` o sin
    override siguen el modo global: `fixedPerChampion` usa el `fixedPage` del override si hay
    uno guardado y, si no, la general, y lo dice; `general` manda la general; `adaptive` (el
    default) manda la **adaptada** (P7-10: con la Fase 7 hecha, "adaptativo" significa lo que
    dice).
  - **Spells.** `.fixed` manda `fixedSpells` con la misma regla de Flash D/F (§13.3);
    `.recommended` y `.unknown`, el par adaptado del motor.
  - **Ítems.** `.fixedSet` manda `fixedItems` como el set de Mito (título `Mito · Ahri MID`,
    uid `mito-<id>`, con los títulos de bloque del usuario); `.skip` no importa ningún set y
    **no borra** el set de Mito que ya exista (no se lee ni se escribe `/lol-item-sets`);
    `.recommended` y `.unknown`, la build adaptada del motor.
  - Un modo fijo sin valor guardado (`fixedPage`, `fixedSpells` o `fixedItems` en `nil`) usa la
    parte **general** (no la adaptada, así el aviso dice la verdad) y lo dice.

  Cada fila del toast cuya parte salió del override suma "· override" (página, spells o set
  fijos, o "No se importan" para un `.skip`); si se pidió una fija y no había, suma "· sin fija
  guardada, va la general". Una parte del override no lleva "· muestra baja". Un override que
  no fija nada (solo favorito o excluido, runas en adaptativo, spells e ítems recomendados)
  importa lo mismo que no tenerlo; uno con runas en `.general` además ignora "Fijo por
  campeón".
- **Registro (`import_log`, §17).** Después de cada import se agrega una `ImportLogEntry` por
  parte con `PersonalStore.appendImportLog`: `applied`, `skipped` o `failed`, y un `detail` de
  códigos sin datos personales (`disabled`, `not_in_loadout`, `already_selected`,
  `no_editable_page`, `needs_confirmation`, `invalid_rune_page`, `lcu`, `unsupported_map`,
  `no_account`, más `override` o `no_fixed_choice` separados por coma). `game_id` va en `NULL`:
  la sesión de champ select no trae el ID de la partida. Confirmar el reemplazo de la página
  suma otra entrada de runas. Sin snapshot no se importa nada y no se registra nada; un fallo
  al escribir el registro no cambia el import.
- **Feedback.** El `ImportReport` se muestra como toast arriba de la ventana principal si
  está abierta y Mito está en primer plano (`NSApp.isActive`); se cierra solo a los 6 s y
  VoiceOver lo anuncia. Si no, va como notificación `.loadoutImported` (§22.5) con el mismo
  título: "Importado para Ahri MID", "Confirmá las runas para Ahri MID" o "No se pudo
  importar todo para Ahri MID". Si todas las partes se saltearon, no se avisa nada.
  La ventana lo aloja con el modificador `.importToast()` en `MainWindowView`, que además le
  avisa al modelo cuándo está abierta.
- **Confirmación de runas.** Un `.needsConfirmation` queda pendiente en el toast (no se cierra
  solo) y en la sección de toggles de la barra de menú, con "Reemplazar" y "Ahora no". Nunca se
  confirma solo. "Reemplazar" vuelve a aplicar **solo las runas** con
  `confirmedReplacement` = ese `pageID`; spells e ítems no se reenvían.
- **Re-import (P7-11).** Con `reimportOnOpponentChange` (default on), cada evento de sesión del
  campeón **lockeado** que ya se importó recalcula el rival de lane y el perfil rival con el rol
  de ese import. Si alguno cambió, se vuelve a armar el plan (mismos overrides y toggles) y se
  re-envía **solo la parte cuya recomendación cambió**: la página, el par de spells o el item
  set (por ejemplo, los situacionales). Solo cuenta una parte que Mito dejó en el cliente
  (aplicada, o spells ya elegidos); una que falló, se salteó o espera confirmación no se toca.
  Las partes que vienen del override (fijas, "no importar") o de la general no cambian con el
  contexto y nunca se re-envían. El contexto nuevo se guarda antes de mandar nada, así el
  próximo evento de la sesión no repite el mismo re-import. Va por el mismo `LoadoutImporter`
  (que serializa los applies), con el título y el `summonerId` del primer import.
  - **No pisar cambios manuales** (`preserveManualChanges`, default on). Antes de re-enviar
    una parte se lee lo que tiene el cliente y se compara con lo que mandó Mito: la página
    `Mito · <título>` de `GET /lol-perks/v1/pages` (`RuneImporter.mitoPage`; tiene que seguir
    siendo la **actual**: si el usuario puso otra página como actual, incluso otra de Mito,
    cuenta como cambio), los spells del jugador local en la sesión (sin orden, porque la regla
    de Flash pudo darlos vuelta), y el set `mito-<id>` de `/lol-item-sets`
    (`ItemSetImporter.mitoItemSet`). Si no coincide (o ya no está), esa parte no se re-envía,
    pasa a ser del usuario por el resto del champ select y la fila dice "Runas sin tocar: las
    cambiaste a mano" (o "Spells/Ítems sin tocar: los cambiaste a mano"). Una lectura que
    falla deja la parte sin enviar como `lcu`. Apagado, se pisa sin leer.
  - **Confirmación pendiente.** Un `.needsConfirmation` sin responder nunca se pisa: las runas
    no se re-envían, el toast de la pregunta queda, y el re-import se avisa como notificación.
    "Reemplazar" después manda la página por la que se preguntó.
  - **Feedback.** Toast (o notificación) con el porqué y lo actualizado: "Rival revelado: Zed ·
    runas e ítems actualizados", o "Cambió el equipo rival · ítems actualizados" si el rival no
    cambió; "nada actualizado" si todas se dejaron por cambios manuales. Solo lleva filas de
    las partes re-enviadas o dejadas, con los marcadores de adaptación de siempre.
  - **Registro.** Una `ImportLogEntry` por parte considerada, con `reimport` en `detail`
    (`reimport`, `lcu,reimport`, …) y `manual_change,reimport` (`skipped`) para las que se
    dejaron por cambios manuales.
  - **Límites (§5).** Solo en champ select: el `Delete` de la sesión (que llega al empezar la
    partida) o una desconexión borra lo recordado, y el siguiente champ select importa de cero.
    Un hover no re-importa, y cambiar de campeón es un import nuevo.

### 13.2 Runas

Lo hace `RuneImporter` en `MitoImport`:
`apply(_ page: RunePage, title: String, settings: ImportSettings, confirmedReplacement: Int?)`.
El nombre de la página es `Mito · <title>`. Con `importRunes` apagado no lee ni envía nada.

**Estrategia de páginas** (`runePageTarget = .mitoPage`, el default):

1. Mito administra **una** página propia, identificada por prefijo en el nombre:
   `Mito · Ahri MID vs Zed`. Solo cuentan las páginas con `isEditable: true`; si hay más de
   una, se usa la actual y si no, la primera.
2. Si ya existe una página "Mito ·", se **edita** (`PUT /lol-perks/v1/pages/{id}`), haya cupo
   o no.
3. Si no existe y hay cupo, se **crea** (`POST /lol-perks/v1/pages`). Hay cupo si las páginas
   propias (`isDeletable` distinto de `false`) son menos que `ownedPageCount` de
   `/lol-perks/v1/inventory`; sin `ownedPageCount` se asume que no hay cupo.
4. Si no hay cupo, la página activa nunca es de Mito (el paso 2 ya la habría editado), así
   que no se envía nada y se pide confirmación en la UI con el id y el nombre de la página
   activa. Si el usuario acepta, se vuelve a llamar con `confirmedReplacement` = ese id y se
   reemplaza, siempre que siga siendo la activa. Si la activa no es editable (páginas por
   defecto del cliente), no hay dónde escribir.
5. Se marca como página actual (`"current": true` en el mismo `POST` o `PUT`).

Opciones de Settings (§21.4): con `.reservedPage` se edita siempre la página
`reservedRunePageID` sin pedir confirmación (si no está configurada, no existe o no es
editable, no se envía nada); con `.currentPage` se reemplaza la página activa sin pedir
confirmación, si es editable. Nunca se borra una página.

**Releer lo que puso Mito** (para el re-import, §13.1). `PerkPage` decodifica también
`primaryStyleId`, `subStyleId` y `selectedPerkIds` (un valor ausente o de otro tipo queda en
`nil` sin perder la página), y `PerkPage.runePage` los vuelve `RunePage` solo si están los
tres. `RuneImporter.mitoPage(in:title:)` devuelve la página que dejó un import de ese título:
la regla del paso 1 (el mismo código que usa el importador) más el nombre exacto
`Mito · <title>`.

Payload (igual para `POST` y `PUT`):

```json
{
  "name": "Mito · Ahri MID vs Zed",
  "primaryStyleId": 8100,
  "subStyleId": 8200,
  "selectedPerkIds": [8112, 8139, 8140, 8135, 8226, 8210, 5008, 5008, 5001],
  "current": true
}
```

`selectedPerkIds` va en orden: 4 de la primaria (keystone + 3), 2 de la secundaria y 3
shards (ofensa, flex, defensa). **Validar siempre** antes de enviar, contra
`/lol-perks/v1/styles` (`LCUEndpoint.perkStyles`, decodificado a `PerkStyle`: `kKeyStone` →
`keystone`, `kMixedRegularSplashable` → `regular`, `kStatMod` → `statMod`). Una página
inválida no se envía (en el cliente deja al usuario sin runas). Reglas, por tipo de fila y
nunca por su posición en `slots`:

- Exactamente 9 perks; primaria y secundaria distintas y presentes en los estilos del cliente.
- La primaria tiene que tener 1 fila keystone, 3 `regular` y 3 `statMod`; la secundaria, al
  menos 2 `regular`.
- Perk 1 de la fila keystone de la primaria; perks 2–4 de sus filas `regular`, en orden.
- Perks 5–6 de filas `regular` **distintas** de la secundaria (en cualquier orden; nunca su
  keystone).
- Shards 7–9 de las filas `statMod` de la primaria, en orden. Se valida fila por fila porque
  un mismo shard aparece en más de una (§16.2).

Resultado (`RuneImportResult`, sin reintentos): `.created`, `.updated(pageID:)` (página Mito
o reservada), `.replacedCurrentPage(pageID:)` (con `.currentPage` o tras confirmar),
`.needsConfirmation(pageID:pageName:)`, `.noEditablePage`, `.invalid(RunePageValidationError)`,
`.disabled` o `.failed(LCUError)`.

Verificar al implementar si los shards cambiaron de estructura (Riot los modificó varias
veces). La fuente de verdad es `perkstyles.json` del parche actual. Sin verificar contra un
cliente real todavía: que el `PUT` con `"current": true` active la página y el límite de
largo del nombre.

### 13.3 Summoner spells

- `PATCH /lol-champ-select/v1/session/my-selection` con `spell1Id` y `spell2Id`
  (`LCUEndpoint.updateMySelection(spells:)`). Lo hace `SpellImporter` en `MitoImport`, que
  devuelve `SpellImportResult`: `.applied(par enviado)`, `.skipped(.disabled |
  .alreadySelected)` o `.failed(LCUError)`, sin reintentos.
- **Respetar la posición de Flash del usuario** (`ImportSettings.flashPosition`). Con `f`,
  Flash siempre va en `spell2Id`; con `d`, siempre en `spell1Id`. Con `auto`, Flash queda en
  el slot donde el jugador local ya lo tiene en la sesión de champ select; si su selección
  actual no tiene Flash (o no aparece en la sesión), se respeta el orden recomendado. Antes,
  `ImportModel` resuelve `auto` con el slot detectado del historial (§21.1,
  `OnboardingModel.resolvedFlashSlot(.auto)`, que lee por un lector inyectado desde
  `AppModel`) y le pasa al importador una copia de los settings con `d` o `f`; solo sin
  mayoría detectada (sin historial, empate o base ilegible) queda la regla de la sesión. Un
  par sin Flash se envía en su propio orden.
- No se envía nada si `importSpells` está apagado o si el par resultante ya es la selección
  actual.
- El override por campeón y rol (`.fixed`, §13.1 y §21.5) manda `fixedSpells` con la misma
  regla de Flash. Pendiente: un modo "fijo por rol" para todos los campeones (por ejemplo, "en
  jungla siempre Smite + Flash").

IDs comunes (verificar con `summoner.json`; hasta entonces el importador fija Flash en 4):
Flash 4, Ignite 14, Teleport 12, Smite 11, Exhaust 3, Heal 7, Barrier 21, Cleanse 1, Ghost 6.

### 13.4 Item sets

- Se envía la lista **completa** de sets del usuario: hay que leer, quitar los sets de
  Mito, agregar el nuevo y hacer `PUT`. Nunca pisar los sets propios del usuario.
- Lo hace `ItemSetImporter` en `MitoImport` con `LCUEndpoint.itemSets(summonerId:)` (GET) y
  `LCUEndpoint.replaceItemSets(_:summonerId:)` (PUT); el `summonerId` sale de
  `CurrentSummoner`. Devuelve `ItemSetImportResult`: `.applied`, `.disabled` (si
  `importItemSets` está apagado no se envía nada) o `.failed(LCUError)`, sin reintentos.
- La lista se modela como objetos JSON crudos (`LCUItemSets`): cada set que no es de Mito
  vuelve en el `PUT` tal cual llegó, con los campos que Mito no modela, en el mismo orden.
  Lo mismo los miembros de primer nivel (`accountId`, `timestamp`, …). Si el `GET` falla o
  la lista no se puede leer entera, **no se hace `PUT`**: una lista parcial borraría los
  sets del usuario.
- Los sets de Mito se identifican por `title` con prefijo `Mito ·` **y** `uid` con prefijo
  `mito-`; hacen falta los dos. Un título que solo contiene "Mito" es del usuario.
- Opción "limpiar sets de Mito viejos" (`cleanOldItemSets`): prendida, se quitan todos los
  sets de Mito y queda solo el del campeón actual; apagada, se quitan solo los sets de Mito
  cuyo `associatedChampions` incluye al campeón actual, así queda uno por campeón.
- El set nuevo va al final de la lista, con `uid` `mito-<championId>` y `title`
  `Mito · <texto>` (el texto lo arma quien llama). Pendiente: validar los ítems contra
  `items.json` del parche antes de enviar.
- `ItemSetImporter.mitoItemSet(in:champion:)` relee los bloques del set de Mito de un campeón
  (`uid` `mito-<championId>` y la misma regla de título y `uid` de arriba) como `ItemSet`, o
  `nil` si no hay. Un bloque sin `type` o un ítem sin `id` numérico en string (o con `count`
  que no es entero) se deja afuera; sin `count`, cuenta 1. Es para el re-import (§13.1).
- Bloques de la build (P6-06), uno por `BuildLayer` elegido y en este orden: "Inicio"
  (`start`), "Núcleo" (`core`), "Botas" (`boots`), "4.º ítem" (`fourth`), "5.º ítem" (`fifth`)
  y "6.º ítem" (`sixth`), del catálogo `Import.xcstrings`. La build adaptada (P7-10, §18.7)
  puede sumar al final "Situacionales" (`LoadoutSelection.situationalBlockTitle`,
  `situational`): flags y después situacionales. Sin WR ni explicación en el título todavía
  (el motivo va en el toast, §13.1); el ejemplo de abajo muestra hacia dónde va.

Estructura:

```json
{
  "accountId": 123456,
  "timestamp": 1760000000000,
  "itemSets": [
    {
      "uid": "mito-103",
      "title": "Mito · Ahri MID vs Zed",
      "type": "custom",
      "map": "SR",
      "mode": "any",
      "associatedChampions": [103],
      "associatedMaps": [11],
      "sortrank": 0,
      "startedFrom": "blank",
      "preferredItemSlots": [],
      "blocks": [
        { "type": "Inicio (54,8 % WR)", "items": [ {"id": "1056", "count": 1}, {"id": "2003", "count": 2} ] },
        { "type": "Core", "items": [ {"id": "6655", "count": 1}, {"id": "3020", "count": 1}, {"id": "4645", "count": 1} ] },
        { "type": "vs mucho AD: Zhonya primero", "items": [ {"id": "3157", "count": 1} ] },
        { "type": "Situacionales", "items": [ {"id": "3135", "count": 1}, {"id": "3102", "count": 1} ] },
        { "type": "Habilidades: Q > W > E (Q-W-E-Q-Q-R)", "items": [] }
      ]
    }
  ]
}
```

Los `type` de los bloques se usan como texto explicativo dentro del cliente. Los IDs de
ítem van como string. Validar contra `items.json` del parche y no incluir ítems retirados.

### 13.5 Importador

`LoadoutImporter` en `MitoImport` aplica un `Loadout` entero con los tres importadores
(§13.2–13.4) y devuelve un `ImportReport` con un resultado por parte:

```swift
public actor LoadoutImporter {
    public init(connection: any LCUConnection)
    public func apply(
        _ loadout: Loadout, settings: ImportSettings, context: LoadoutImportContext
    ) async -> ImportReport
}

public struct LoadoutImportContext: Sendable {
    let title: String                // "Ahri MID vs Zed": página de runas e item set
    let champion: ChampionID
    let map: ItemSetMap              // default .summonersRift
    let session: ChampSelectSession  // Flash y "ya seleccionado" de los spells
    let summonerId: Int              // de CurrentSummoner, para los item sets
    let confirmedReplacement: Int?   // el pageID de un .needsConfirmation aceptado
}

public struct ImportReport: Equatable, Sendable {
    var runes: StepResult
    var spells: StepResult
    var items: StepResult
}

public enum StepResult: Equatable, Sendable {
    case applied
    case skipped(StepSkipReason)   // .notInLoadout, .disabled, .alreadySelected, .noEditablePage
    case failed(StepError)         // .lcu(LCUError), .invalidRunePage(RunePageValidationError)
    case needsConfirmation(pageID: Int, pageName: String)
}
```

- Una parte `nil` del `Loadout` queda `.skipped(.notInLoadout)` sin tocar el cliente.
- Los pasos son independientes (uno que falla no frena a los otros) y corren siempre en el
  mismo orden, runas → spells → ítems, para que el orden de escrituras al LCU sea
  determinista. No se paralelizan.
- `.needsConfirmation` de runas llega tal cual: la UI ofrece reemplazar la página y, si el
  usuario acepta, vuelve a llamar con `confirmedReplacement` = ese `pageID`. Una página
  inválida es `.failed(.invalidRunePage(_))`; `.noEditablePage` es un skip.
- Dos `apply` superpuestos (hover y después lock) no se intercalan: el segundo espera a que
  termine el primero.
- El skill order no se importa (el cliente no tiene API) y no aparece en el reporte; quien
  arma el item set puede mostrarlo como un bloque (§13.4). No se loguea el contenido del
  loadout ni datos de identidad.
- `Loadout.explanation` (`[Reason]`, vacío por defecto) dice por qué se eligió cada parte
  (`LoadoutPart`: runas, spells, una capa de ítems, skill order): elección general con uso y
  winrate, adaptada al rival o al perfil rival, o un ítem por flag o situacional (§18.6–§18.8).
  El importador no la envía al cliente; la dibuja la UI (`ReasonRow`, §22.3).

El resultado se muestra como un toast nativo en la ventana y como notificación si la
ventana no está visible.

---

## 14. Pipeline de datos (mito-data)

> Vive en el repo privado `mito-data`, no en este. Esta sección es su especificación; el
> contrato con la app es el schema de §17 (ADR 0005).

### 14.1 Objetivo

Producir, **por parche y por bracket de elo**, un snapshot SQLite con todas las
estadísticas agregadas que necesita el motor. Escrito en Python.

### 14.2 Etapas

```
seed ──▶ discover players ──▶ discover matches ──▶ fetch match (+timeline)
                                                        │
                                                        ▼
                                              normalize ──▶ parquet (raw)
                                                                │
                                                                ▼
                                       aggregate (DuckDB) ──▶ tablas agregadas
                                                                │
                                                                ▼
                                       export ──▶ <bracket>.sqlite.xz + tips
                                                                │
                                                                ▼
                                       publish ──▶ hosting + manifest.json
```

### 14.3 Seed y descubrimiento de jugadores

- Regiones iniciales: **LAS (la2)**, LAN (la1), NA (na1), BR (br1), todas bajo el ruteo
  regional `americas`. Luego EUW y KR para tener volumen de alto elo.
- Seed: `league-v4` challenger, grandmaster y master, más `entries` para Diamond y Emerald
  (paginado).
- league-v4 hoy expone `puuid` en las entradas. Usarlo directamente (los `summonerId` están
  deprecados).
- Cada jugador descubierto entra en la tabla `players(puuid, region, tier, division, lp,
  last_crawled_at)`.

### 14.4 Descubrimiento de partidas

- `GET /lol/match/v5/matches/by-puuid/{puuid}/ids?queue=420&type=ranked&startTime=<inicio
  del parche>&count=100`
- Solo cola 420 (Solo/Duo) en la v1. Flex (440) y Normal Draft (400) usan el snapshot de 420
  (§20.3).
- Se deduplica por `matchId` (`matches_seen`).
- Se priorizan jugadores de más alto elo y los menos recientemente crawleados.

### 14.5 Descarga

- `GET /lol/match/v5/matches/{matchId}`: participantes, ítems finales, runas, spells, bans
  y estadísticas.
- `GET /lol/match/v5/matches/{matchId}/timeline`: orden de compra de ítems, orden de
  habilidades, power spikes y diffs @15. Se pide para una **muestra estratificada**: siempre
  que la partida tenga algún (campeón, rol) con menos de ~150 timelines en el parche, y si no,
  a una tasa base (por ejemplo, 30 %). El orden de build converge con menos datos que los
  winrates, y así ningún (campeón, rol) se queda sin loadout general (§14.12).
- Filtros al normalizar:
  - Descartar remakes (`gameDuration < 300` s o `gameEndedInEarlySurrender`).
  - Descartar partidas de un parche distinto al objetivo.
  - Verificar `teamPosition` válido para los 10 participantes. Si falta, descartar o
    marcar.

### 14.6 Rate limiting

- Dev key: 20 requests por segundo y 100 cada 2 minutos, y **expira cada 24 h**. Sirve para
  prototipar.
- Personal key: pedirla en el portal para uso propio y sostenido.
- Production key: necesaria para una app pública. Límites mucho mayores.
- Verificar los límites vigentes en el portal antes de dimensionar.
- Implementación: **token bucket por (key, ruteo)** respetando ambos niveles (app y método)
  y leyendo `X-App-Rate-Limit`, `X-Method-Rate-Limit` y `Retry-After`. Ante un 429, dormir
  `Retry-After` y reintentar.

```python
class DualWindowLimiter:
    """Respeta N req / ventana corta y M req / ventana larga."""
    def __init__(self, limits: list[tuple[int, float]]):  # [(20, 1.0), (100, 120.0)]
        self.limits = limits
        self.history: deque[float] = deque()
        self.lock = asyncio.Lock()

    async def acquire(self) -> None:
        async with self.lock:
            while True:
                now = time.monotonic()
                wait = 0.0
                for count, window in self.limits:
                    recent = [t for t in self.history if now - t < window]
                    if len(recent) >= count:
                        wait = max(wait, window - (now - recent[0]))
                if wait <= 0:
                    self.history.append(now)
                    cutoff = now - max(w for _, w in self.limits)
                    while self.history and self.history[0] < cutoff:
                        self.history.popleft()
                    return
                await asyncio.sleep(wait)
```

**Volumen estimado con una key de 100 req/2 min:** unas 72.000 requests por día. Con
match + timeline son unas 36.000 partidas por día y por key. Un parche de dos semanas da
unas 400.000–500.000 partidas: suficiente para winrates por campeón y rol, y para matchups
de los pares comunes en un bracket amplio (Esmeralda+).

### 14.7 Raw store

- Parquet particionado: `raw/participants/region=la2/patch=16.21/part-*.parquet`.
- Tablas raw:
  - `matches`: match_id, region, patch, queue_id, game_start, duration_s, winning_team.
  - `participants`: una fila por jugador por partida (ver columnas abajo).
  - `bans`: match_id, team_id, champion_id, pick_turn.
  - `item_events`: match_id, puuid, ts_ms, item_id, event (purchase/sell/undo).
  - `skill_events`: match_id, puuid, ts_ms, skill_slot.
- Guardar el JSON crudo comprimido (zstd) solo durante el desarrollo, para poder reprocesar.

Columnas de `participants`:

```
match_id, puuid, team_id, win, champion_id, team_position, tier_bracket,
summoner1_id, summoner2_id,
primary_style, sub_style, perk0..perk5, stat_offense, stat_flex, stat_defense,
item0..item6,
kills, deaths, assists, cs_total, gold_earned,
dmg_to_champs, phys_dmg_to_champs, magic_dmg_to_champs, true_dmg_to_champs,
dmg_taken, dmg_self_mitigated, time_ccing_others, vision_score,
gold_at_15, cs_at_15, xp_at_15        -- desde la timeline cuando exista
```

### 14.8 Bracket de elo de una partida

match-v5 no trae el elo. Se estima:

- Se siembra toda la escalera Esmeralda IV+ de cada plataforma vía league-v4 (cacheado por
  jugador). Un participante que no está en esa escalera cuenta como debajo de Esmeralda.
- Una partida es `emerald_plus` si al menos 6 de sus 10 participantes son Esmeralda+ (la
  mediana inferior). La "mediana de los tiers conocidos" se descartó: con solo Esmeralda+
  sembrado, todo tier conocido es Esmeralda+ y la mediana queda sesgada. `diamond_plus` es el
  mismo filtro con Diamante+.
- Brackets que publica Mito: `emerald_plus` (base, siempre se descarga) y `diamond_plus`
  (capa opcional que el usuario activa). `master_plus` no se publica hasta que el volumen
  medido lo justifique. Cada bracket incluye a los de más arriba, así que el backoff a un
  bracket más amplio es consultar el archivo base.

### 14.9 Normalización de parche

- `info.gameVersion` es un string tipo `"X.Y.build.algo"`. Se toma `X.Y` como clave interna.
- La nomenclatura comercial de los parches cambió (por ejemplo, "25.S1.2" en 2025 y
  numeración por año en 2026). Mito **no** hardcodea formatos: mantiene una tabla `patches`
  con `game_version_prefix`, `display_name`, `start_date` y la versión de Data Dragon
  correspondiente.

### 14.10 Agregación (DuckDB)

Cada agregación corre una vez por bracket exportado, filtrando las partidas de ese bracket o
más alto. Ejemplo de stats por campeón y rol:

```sql
CREATE OR REPLACE TABLE champ_role_stats AS
SELECT p.champion_id, p.team_position AS role,
       COUNT(*)                     AS games,
       COUNT(*) FILTER (WHERE p.win) AS wins,
       SUM(p.kills) AS kills, SUM(p.deaths) AS deaths, SUM(p.assists) AS assists,
       SUM(p.cs_total)              AS cs,
       ROUND(SUM(m.duration_s) / 60) AS minutes
FROM participants p JOIN matches m USING (match_id)
WHERE p.tier_bracket IN $bracket_tiers
GROUP BY ALL;
```

Ejemplo de matchups (mismo rol, equipos opuestos; el join ya produce las dos orientaciones):

```sql
CREATE OR REPLACE TABLE matchup_stats AS
SELECT a.champion_id, a.team_position AS role, b.champion_id AS opp_id,
       COUNT(*)                         AS games,
       COUNT(*) FILTER (WHERE a.win)    AS wins,
       COUNT(a.gold_at_15)              AS tl_games,
       AVG(a.gold_at_15 - b.gold_at_15) AS gold_diff_15,
       AVG(a.cs_at_15   - b.cs_at_15)   AS cs_diff_15
FROM participants a
JOIN participants b
  ON a.match_id = b.match_id
 AND a.team_position = b.team_position
 AND a.team_id <> b.team_id
WHERE a.tier_bracket IN $bracket_tiers
GROUP BY ALL
HAVING COUNT(*) >= 30;
```

Sinergias (mismo equipo):

```sql
CREATE OR REPLACE TABLE synergy_stats AS
SELECT a.champion_id, a.team_position AS role,
       b.champion_id AS ally_id, b.team_position AS ally_role,
       COUNT(*) AS games, COUNT(*) FILTER (WHERE a.win) AS wins
FROM participants a
JOIN participants b
  ON a.match_id = b.match_id AND a.team_id = b.team_id AND a.puuid <> b.puuid
WHERE a.tier_bracket IN $bracket_tiers
GROUP BY ALL
HAVING COUNT(*) >= 50;
```

**Perfil rival por partida.** Después de calcular `champion_profiles`, cada equipo de cada
partida se clasifica con las mismas `profile_rules` que van en `meta` (§18.4), aplicadas a los
perfiles de sus campeones y no al daño real de esa partida. Es lo mismo que puede hacer la app
en champ select, así que los dos hablan del mismo perfil. Un equipo cuenta en todos los
perfiles que cumple.

Tablas a producir (contrato en la sección 17):

- `champion_roles`, `champ_role_stats`, `champ_ban_stats`, `champ_vs_profile`
- `matchup_stats`, `synergy_stats`, `vs_team_stats` (contra campeones en cualquier rol)
- `rune_page_defs`, `rune_pages`, `rune_page_vs_profile`
- `item_builds` (start, core de 3, boots, 4.º a 6.º), `item_vs_profile` (con la línea base
  `'any'`, desde ítems finales)
- `spell_pairs`, `skill_orders`
- `duration_curves` (winrate por bucket de duración)
- `champion_profiles` (daño, tanqueo, CC y power spikes)
- Estáticos y curados: `champions`, `champion_flags`, `item_classes`

### 14.11 Perfiles de campeón (derivados de datos)

Se calculan desde match-v5 y la timeline:

| Métrica | Fuente | Uso |
|---|---|---|
| `phys_share`, `magic_share`, `true_share` | daño a campeones de cada tipo / total | Perfil AD/AP |
| `dmg_per_min` | dmg_to_champs / minutos | Peso de cada campeón en el perfil de daño del equipo |
| `tankiness` | (dmg_taken + dmg_self_mitigated) por minuto, percentil en el rol | Frontline |
| `cc_score` | time_ccing_others por minuto, percentil en el rol | CC del equipo |
| `gold_diff_15` | timeline, vs el rival de lane | Fuerza de lane |
| `lvl6_s` | timeline: primer `SKILL_LEVEL_UP` de la R, mediana | Power spikes |
| `item1_s`..`item3_s` | timeline: compra del 1.º, 2.º y 3.º legendario, mediana | Power spikes |

La fuerza early y late no se guarda: sale de `duration_curves` (§18.4).

Lo que los datos no capturan bien se cura a mano por parche en `mito-data`
(`src/mito_data/champion_flags.toml`, TOML que lee la stdlib de Python) y se exporta como `champion_flags`: `high_heal`,
`point_click_cc`, `auto_attacker`, `poke` y `engage`. Reemplaza a los `tags` de Data Dragon
y a las listas estáticas.

### 14.12 Export

- Un archivo por (schema_version, parche, cola, bracket):
  `schema-1/16.21/420/emerald_plus.sqlite.xz`. `emerald_plus` es la base y se publica
  siempre; `diamond_plus` es una capa opcional con el mismo schema; `master_plus` no se
  publica hasta que el volumen medido lo justifique.
- Se exportan solo filas que pasan el mínimo de §18.2. Los mínimos salen de la misma config
  que se escribe en `meta.thresholds`. Excepciones: `champion_roles` va completa (la
  inferencia de roles necesita los roles raros) y las filas que exige la regla de completitud.
- **Regla de completitud** (archivo base): cada fila de `champ_role_stats` tiene, en general
  (`opp_id = 0`), al menos una página de runas, un par de spells, un inicio, un core, unas
  botas y un orden de habilidades. Se logra con el muestreo estratificado de timelines (§14.5)
  y, para core y botas, con un fallback desde ítems finales cuando `champion_profiles.tl_games` no
  llega al mínimo de `build_layer`: core = la combinación de 3 legendarios finales más frecuente (ordenada por
  frecuencia de cada ítem), botas = las tier 2 finales más frecuentes. Si ninguna opción pasa
  el mínimo se exporta la más frecuente (la app la marca "muestra baja"). Si aun así falta
  algo, el export falla.
- `VACUUM` y compresión **xz** (`.sqlite.xz`): el framework Compression de Apple decodifica
  LZMA/xz de forma nativa; zstd no.
- **Presupuesto de tamaño**, que controla el exporter por archivo: aviso a 4 MB comprimido;
  límite duro de 8 MB comprimido y 32 MB sin comprimir. Si se pasa, poda en este orden,
  midiendo después de cada paso, y falla si sigue pasado:
  1. `item_builds` por rival, salvo `start`.
  2. Páginas de runas y pares de spells por rival con menos de 300 partidas.
  3. Mínimo de `synergy_stats` a 100.
  4. Mínimo de `vs_team_stats` a 100.
  5. `item_vs_profile` limitado a los 10 primeros por (champ, role, perfil).

  Nunca se podan: `meta`, `champions`, `champion_roles`, `champ_role_stats`,
  `champion_profiles`, `duration_curves`, los loadouts generales, `matchup_stats` ≥ 30,
  `champ_vs_profile`, `item_classes` y `champion_flags`.
- Estimación medida: ~1,2–1,9 MB comprimido por archivo `emerald_plus` (3,6–5,7 MB sin
  comprimir).
- **Tips de matchup curados** (no van en el snapshot): se escriben a mano en `mito-data`
  (`curated/tips/<locale>.yaml`, por par de campeones y rol) y se exportan como archivo propio
  por locale, listado en el manifest. es-AR primero. Van a su ritmo, no al del parche: cada
  tip lleva el último parche en que se revisó.

```json
{
  "format_version": 1,
  "locale": "es-AR",
  "tips": [
    { "champion_id": 103, "role": "MIDDLE", "opp_id": 238, "reviewed_patch": "16.20",
      "text": "Guardá la E para cuando entra la R de Zed." }
  ]
}
```

`opp_id = 0` es un tip general del campeón en ese rol.

- **Fixture:** `mito-data fixture` genera un snapshot chico y su schema en
  `fixtures/snapshot/` de este repo. Se regenera con cada cambio de `schema_version`.
- `manifest.json`. `sha256` y `bytes` son del archivo comprimido; `raw_bytes`, del SQLite
  descomprimido. La app ignora entradas con un `schema_version` que no soporta; durante una
  transición se publican las dos versiones.

```json
{
  "generated_at": "2026-10-20T12:00:00Z",
  "current_patch": "16.21",
  "ddragon_version": "16.21.1",
  "snapshots": [
    {
      "schema_version": 1,
      "patch": "16.21",
      "queue": 420,
      "bracket": "emerald_plus",
      "url": "https://data.example/schema-1/16.21/420/emerald_plus.sqlite.xz",
      "sha256": "…",
      "bytes": 1650000,
      "raw_bytes": 4900000,
      "matches": 412339,
      "regions": ["la2", "la1", "na1", "br1"]
    }
  ],
  "tips": [
    {
      "format_version": 1,
      "locale": "es-AR",
      "url": "https://data.example/tips/1/es-AR.json",
      "sha256": "…",
      "bytes": 48211,
      "updated_at": "2026-10-18T09:00:00Z"
    }
  ]
}
```

### 14.13 Inicio de parche (cold start)

Los primeros 2–3 días de un parche hay pocos datos. La mezcla la hace el **exporter**:

- A cada tabla de conteos se le suman los conteos del parche anterior escalados por
  `w_viejo = k / (n_nuevo + k)`, con `k = meta.blend_k` (≈ 20.000) y `n_nuevo` = partidas del
  parche nuevo en el bracket. Se redondea a enteros; las medias se ponderan por `tl_games`.
- Los campeones con `champions.changed = 1` (cambiados en las notas del parche: lista manual en
  `mito-data` o heurística por la diferencia de winrate) no reciben datos del parche anterior.
- Con `w_viejo < 0,05` se deja de mezclar.
- `meta.blend_patches` lista los parches mezclados y `meta.matches` ya incluye la mezcla.
- La app guarda solo el archivo actual, nunca el del parche anterior, y muestra "Datos
  16.21 + 16.20" desde `meta.blend_patches` cuando hay más de uno.

### 14.14 Scheduling

- `crawl`: continuo (daemon) o cada hora.
- `aggregate + export + publish`: cada 12–24 h, más uno al detectar un parche nuevo.
- Detección de parche nuevo: `https://ddragon.leagueoflegends.com/api/versions.json`.
- Corre en una máquina propia, una VPS o Jenkins. Requisitos modestos: unos GB de disco por
  parche en parquet.

### 14.15 CLI

```bash
uv run mito-data seed      --region la2 --tiers MASTER,GRANDMASTER,CHALLENGER,DIAMOND,EMERALD
uv run mito-data crawl     --regions la2,la1,na1,br1 --patch current --workers 4
uv run mito-data aggregate --patch 16.21
uv run mito-data export    --patch 16.21 --brackets emerald_plus,diamond_plus
uv run mito-data tips      --locale es-AR         # exporta los tips curados
uv run mito-data fixture   --out ../mito/fixtures/snapshot
uv run mito-data publish   --patch 16.21
uv run mito-data static    --version latest       # descarga Data Dragon / CDragon
uv run mito-data stats     --patch 16.21          # resumen de volumen y calidad
```

---

## 15. Riot API pública

### 15.1 Ruteo

| Tipo | Valores | Se usa para |
|---|---|---|
| Plataforma | `la2` (LAS), `la1` (LAN), `br1`, `na1`, `euw1`, `kr`, … | league-v4, summoner-v4, champion-mastery-v4 |
| Regional | `americas`, `europe`, `asia`, `sea` | account-v1, match-v5 |

Base: `https://{routing}.api.riotgames.com`, con el header `X-Riot-Token: <key>`.

### 15.2 Endpoints

| Endpoint | Ruteo | Uso |
|---|---|---|
| `/riot/account/v1/accounts/by-riot-id/{gameName}/{tagLine}` | regional | puuid desde Riot ID |
| `/lol/league/v4/challengerleagues/by-queue/RANKED_SOLO_5x5` | plataforma | Seed |
| `/lol/league/v4/grandmasterleagues/by-queue/RANKED_SOLO_5x5` | plataforma | Seed |
| `/lol/league/v4/masterleagues/by-queue/RANKED_SOLO_5x5` | plataforma | Seed |
| `/lol/league/v4/entries/RANKED_SOLO_5x5/{tier}/{division}?page=N` | plataforma | Seed Diamond y Emerald |
| `/lol/match/v5/matches/by-puuid/{puuid}/ids` | regional | Ids de partidas |
| `/lol/match/v5/matches/{matchId}` | regional | Partida |
| `/lol/match/v5/matches/{matchId}/timeline` | regional | Timeline |
| `/lol/champion-mastery/v4/champion-masteries/by-puuid/{puuid}` | plataforma | Capa personal profunda (opcional) |

### 15.3 Campos de match-v5 que importan

- `metadata.matchId`, `metadata.participants[]`
- `info.gameVersion`, `info.queueId`, `info.gameDuration`, `info.gameEndedInEarlySurrender`
- `info.teams[].bans[]`, `info.teams[].win`
- `info.participants[]`: `puuid`, `championId`, `teamPosition`, `teamId`, `win`,
  `summoner1Id`, `summoner2Id`, `item0..item6`, `perks.styles[]` (primaryStyle y subStyle
  con `selections[].perk`), `perks.statPerks` (offense, flex, defense), estadísticas de daño,
  `timeCCingOthers`, `visionScore` y `challenges` (métricas extra).

### 15.4 Timeline

- `info.frames[]` cada 60 s, con `participantFrames` (oro, xp, cs) y `events[]`.
- Eventos útiles: `ITEM_PURCHASED`, `ITEM_SOLD`, `ITEM_UNDO`, `SKILL_LEVEL_UP`,
  `CHAMPION_KILL`, `BUILDING_KILL`, `ELITE_MONSTER_KILL`.
- Orden de build: secuencia de `ITEM_PURCHASED` neta de undo, filtrando consumibles y
  componentes con `item_classes` (§16.3). Capas:
  - **Inicio:** compras con `timestamp < 60s`.
  - **Core:** primeros 3 ítems legendarios terminados, en orden.
  - **Botas:** primeras botas de tier 2.
  - **4.º a 6.º:** el legendario terminado en esa posición.
- Power spikes: segundo del primer `SKILL_LEVEL_UP` de la R y de la compra del 1.º, 2.º y 3.º
  legendario. Se exportan las medianas (`champion_profiles`).
- Orden de habilidades: todos los `SKILL_LEVEL_UP` con `levelUpType == NORMAL` (hasta 18). Se
  resume como `max_order`, la prioridad de maxeo (Q > W > E; incluye la R en kits que la suben
  como básica), más la secuencia completa. La UI y el item set muestran la prioridad y los
  primeros 6 niveles; la pestaña Build, la secuencia completa.

---

## 16. Datos estáticos

### 16.1 Fuentes

| Fuente | Qué tiene | Cuándo usarla |
|---|---|---|
| **Cliente local** (`/lol-game-data/assets/v1/...`) | Campeones, ítems, runas, spells e íconos en la versión exacta del cliente | **Prioridad en la app** (offline, versión exacta) |
| **Data Dragon** (`ddragon.leagueoflegends.com`) | JSON y assets oficiales por versión, con locales (incluye `es_AR`) | Pipeline y fallback en la app (lo pide `DataDragonClient` en MitoStore, el único módulo de la app con salida a internet; GET HTTPS solo a este host, sin seguir redirects a otro) |
| **CommunityDragon** (`raw.communitydragon.org`) | Mismos datos del cliente, más completos y con IDs crudos | Pipeline, cuando a Data Dragon le falta algo |

Archivos del cliente que lee la app (`GET /lol-game-data/assets/v1/<archivo>`, endpoints
tipados en `LCUEndpoint+GameData.swift` de LCUKit, que decodifican directo a los tipos de
§16.2): `champion-summary.json`, `items.json`, `perkstyles.json`, `perks.json` y
`summoner-spells.json`.

- `GameDataCatalog` (actor en MitoAssets) los pide los cinco en paralelo la primera vez que
  se llama `load()` y guarda el resultado en memoria, sin disco: el cliente es local.
  `load()` siguiente no hace requests; llamadas concurrentes comparten la misma carga.
  `reload()` vuelve a pedir todo (reconexión o parche nuevo). Una carga fallida no se
  guarda: el próximo `load()` reintenta. Los errores salen como `LCUError`.
- El resultado es `GameData`, un valor inmutable con búsqueda por ID (`champion`, `item`,
  `perk`, `perkStyle`, `spell`) y la lista `perkStyles` en orden del cliente. Si un ID se
  repite, gana el primero.
- Decodificación tolerante: solo `id` es obligatorio (entero). Una entrada sin `id` válido se
  saltea sin tirar el archivo; un campo faltante o con otro tipo queda vacío (`""`, `0`,
  `[]`); las claves desconocidas se ignoran. En `perkstyles.json`, `slots[].type` mapea
  `kKeyStone` → `keystone`, `kMixedRegularSplashable` → `regular`, `kStatMod` → `statMod`
  y cualquier otro valor a `unknown(String)`; una fila sin `type` se saltea. El archivo
  entero falla (`LCUError.decoding`) solo si no es un array (o, en `perkstyles.json`, si no
  trae `styles`).
- `champion-summary.json` incluye el placeholder `-1` ("None"); el catálogo no lo filtra.
- Formas verificadas contra el `rcp-be-lol-game-data` de CommunityDragon (16.20), no contra
  un cliente real.

Archivos de Data Dragon:

- `https://ddragon.leagueoflegends.com/api/versions.json`
- `/cdn/{version}/data/es_AR/champion.json`
- `/cdn/{version}/data/es_AR/item.json`
- `/cdn/{version}/data/es_AR/runesReforged.json`
- `/cdn/{version}/data/es_AR/summoner.json`
- `/cdn/{version}/img/champion/{Name}.png`

### 16.2 IDs

- Los campeones se identifican siempre por **ID numérico** (`103` = Ahri), nunca por nombre.
  El `key` de Data Dragon es el numérico y el `id` es el string.
- Las runas tienen IDs de perk (por ejemplo, 8112) y de estilo (8100 Dominación, 8000
  Precisión, 8200 Brujería, 8300 Inspiración, 8400 Valor). Verificar con `perkstyles.json`.
- Los ítems tienen IDs numéricos. Al exportar se filtran los no comprables en SR y los
  retirados.

Tipos en `MitoCore/GameData/` (valores puros, `Hashable` y `Sendable`, sin `Codable` ni
decodificación; el catálogo los arma desde `/lol-game-data/assets/v1/...`). Los íconos
quedan como el path crudo del asset del cliente (`/lol-game-data/assets/...`), el que recibe
`IconRequest` en MitoAssets.

| Tipo | Campos | De dónde sale |
|---|---|---|
| `Champion` | `id: ChampionID`, `alias` (`"Ahri"`), `name` (locale del cliente), `iconPath` | `champion-summary.json` (`id`, `alias`, `name`, `squarePortraitPath`) |
| `Item` | `id: ItemID`, `name`, `totalGold`, `iconPath`, `itemClass: ItemClass?` | `items.json` (`priceTotal`, `iconPath`); la clase, del snapshot |
| `ItemClass` | `starter`, `consumable`, `component`, `bootsT1`, `bootsT2`, `legendary`, `supportUpgrade`, `unknown(String)` | `item_classes.class` (§16.3, §17); el raw value es esa codificación |
| `PerkStyle` | `id: PerkStyleID`, `name`, `iconPath`, `slots: [Slot]` | `perkstyles.json` |
| `PerkStyle.Slot` | `kind` (`keystone`, `regular`, `statMod`, `unknown(String)`), `perks: [PerkID]` en orden | `slots[].type` y `slots[].perks` |
| `Perk` | `id: PerkID`, `name`, `iconPath` | `perks.json` |
| `SummonerSpell` | `id: SummonerSpellID`, `name`, `iconPath`, `gameModes: Set<String>` (`CLASSIC`, `ARAM`, …) | `summoner-spells.json` |

- La clase de ítem no viene del cliente: `itemClass` es `nil` hasta que se cruza con el
  snapshot, así un `Item` existe sin snapshot (Fase 4) y el importador decide qué hacer.
- Cada estilo trae también las filas de shards (`statMod`); en una página los shards salen
  de las filas `statMod` de la primaria y la secundaria elige solo de filas `regular` (§13.2).
  Un mismo shard puede aparecer en más de una fila, así que "la fila de un perk" no siempre
  es única.

### 16.3 Clasificación de ítems (necesaria para builds)

En el pipeline se clasifica cada ítem como:

- `starter` (Doran's, Cull, ítems de jungla y support iniciales)
- `consumable`
- `component`
- `boots_t1`, `boots_t2`
- `legendary` (terminado)
- `support_upgrade`

Fuente: `item.json` (`into`, `from`, `depth`, `gold.total`, `tags`, `maps`) más una lista
manual chica de excepciones en `data/static/item_overrides.yaml` de `mito-data`, que también
marca los ítems antiheal. La clasificación se publica en el snapshot como `item_classes`
(§17), así la app arma bloques y reglas con la misma clasificación que el pipeline.

El cliente no clasifica ítems: el `Item` que arma `GameDataCatalog` desde `items.json` trae
`itemClass` en `nil`, y la clase se cruza desde `item_classes` del snapshot cuando está
disponible (§16.2).

Botas tier 3 (Spellslinger's, Crimson Lucidity, Gunmetal y demás mejoras tardías): siguen
clasificadas como `boots_t2` en `item_classes`, pero al leer ítems finales (`item_vs_profile`,
incluida la línea base `'any'`, y el fallback de core y botas) el pipeline las cuenta como su
botas tier 2 de origen, la que se compra y la que champ select puede recomendar. Así ítems
finales y timeline hablan de los mismos ids. Decidido antes de publicar el primer snapshot,
sin subir `schema_version`; un cambio así después de publicar sí lo sube.

---

## 17. Modelo de datos del snapshot

Esta sección es el **contrato** entre `mito-data` y la app (ADR 0005). Si el pipeline o la
app no coinciden con ella, manda ella.

Un archivo SQLite de solo lectura por **(schema_version, parche, cola, bracket)**. Esa
identidad está en `meta` y en cada entrada del manifest (§14.12); las filas no la repiten.

Reglas:

- Toda columna de clave primaria es `NOT NULL`. "General" (sin rival) es `opp_id = 0`, nunca
  `NULL`.
- Todas las tablas son `WITHOUT ROWID`, salvo `rune_page_defs` (su `page_id` es el rowid).
- Nada de JSON en claves ni en columnas que se consultan en champ select. Solo algunos valores
  de `meta` son JSON, y se leen una vez al abrir el archivo.
- Se publican **conteos crudos** (`games`, `wins`, sumas). Winrates suavizados, pick rates, ban
  rates, shares y tiers los calcula la app con los parámetros de `meta`, que son los mismos con
  los que filtra el exporter. Así no pueden divergir.
- Las relaciones se escriben en las dos orientaciones (A vs B y B vs A, A con B y B con A):
  no hacen falta índices por rival ni por aliado.
- `vs_team_stats` cierra en las dos orientaciones: para cada par de campeones, A contra B sumado
  sobre los roles exportados de A tiene las mismas partidas que B contra A sumado sobre los de
  B, y las victorias de un lado son las derrotas del otro (solo se exige cuando todos los roles
  de ambos están exportados). Las partidas sin exactamente un equipo ganador no cuentan.
- `duration_curves` reparte las partidas y las victorias de cada (campeón, rol) entre sus
  buckets: para cada uno, la suma de `games` y la de `wins` son las de `champ_role_stats`.
- En `item_builds`, las capas `fourth`–`sixth` de una fila nunca repiten un ítem del core de esa
  misma partida; entre filas sí puede pasar, y la app descarta repeticiones al armar el set.
- Sin nombres localizados ni `tags`: los nombres salen del cliente en su locale (§16, §22.6) y
  lo que antes salía de los tags lo cubre `champion_flags`.
- Cualquier cambio (tabla, columna, semántica o clave de `meta`) sube `schema_version`.
- `mito-data` genera un snapshot chico de ejemplo en `fixtures/snapshot/` para el contract
  test de la app (§23.3).

```sql
-- Metadatos (claves abajo)
CREATE TABLE meta (
  key   TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

-- Estáticos y curados del parche
CREATE TABLE champions (
  champion_id INTEGER NOT NULL PRIMARY KEY,
  key         TEXT NOT NULL,               -- "Ahri", solo para depurar
  changed     INTEGER NOT NULL DEFAULT 0   -- 1 = cambiado en las notas del parche (§14.13)
) WITHOUT ROWID;

CREATE TABLE champion_flags (              -- curado a mano por parche (§14.11)
  champion_id INTEGER NOT NULL,
  flag        TEXT NOT NULL,               -- high_heal | point_click_cc | auto_attacker | poke | engage
  PRIMARY KEY (champion_id, flag)
) WITHOUT ROWID;

CREATE TABLE item_classes (                -- §16.3, ~250 filas
  item_id  INTEGER NOT NULL PRIMARY KEY,
  class    TEXT NOT NULL,                  -- starter | consumable | component | boots_t1 | boots_t2 | legendary | support_upgrade
  antiheal INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;

-- Campeón y rol
CREATE TABLE champion_roles (              -- P(rol | campeón) = games / Σ games del campeón
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,               -- TOP | JUNGLE | MIDDLE | BOTTOM | UTILITY
  games       INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role)
) WITHOUT ROWID;

CREATE TABLE champ_role_stats (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  games       INTEGER NOT NULL,            -- pick_rate = games / meta.matches
  wins        INTEGER NOT NULL,
  kills       INTEGER NOT NULL,            -- sumas, para los promedios de §19.2
  deaths      INTEGER NOT NULL,
  assists     INTEGER NOT NULL,
  cs          INTEGER NOT NULL,
  minutes     INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role)
) WITHOUT ROWID;

CREATE TABLE champ_ban_stats (             -- ban_rate = bans / meta.matches
  champion_id INTEGER NOT NULL PRIMARY KEY,
  bans        INTEGER NOT NULL             -- partidas en las que fue baneado
) WITHOUT ROWID;

CREATE TABLE champion_profiles (           -- §14.11
  champion_id  INTEGER NOT NULL,
  role         TEXT NOT NULL,
  phys_share   REAL NOT NULL,
  magic_share  REAL NOT NULL,
  true_share   REAL NOT NULL,
  dmg_per_min  REAL NOT NULL,
  tankiness    REAL NOT NULL,              -- 0–1, percentil dentro del rol
  cc_score     REAL NOT NULL,              -- 0–1, percentil dentro del rol
  tl_games     INTEGER NOT NULL,           -- partidas con timeline: denominador de lo que sigue
  gold_diff_15 REAL,                       -- media vs el rival de lane
  lvl6_s       INTEGER,                    -- medianas en segundos: R y 1.º–3.º legendario
  item1_s      INTEGER,
  item2_s      INTEGER,
  item3_s      INTEGER,                    -- NULL si no hay muestra de timeline
  PRIMARY KEY (champion_id, role)
) WITHOUT ROWID;

CREATE TABLE duration_curves (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  bucket      TEXT NOT NULL,               -- '<20' | '20-25' | '25-30' | '30-35' | '35-40' | '40+'
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, bucket)
) WITHOUT ROWID;

CREATE TABLE champ_vs_profile (            -- por perfil del equipo rival (multi-label, §18.4)
  champion_id   INTEGER NOT NULL,
  role          TEXT NOT NULL,
  enemy_profile TEXT NOT NULL,             -- heavy_ad | heavy_ap | mixed | heavy_cc
  games         INTEGER NOT NULL,
  wins          INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_profile)
) WITHOUT ROWID;

-- Relaciones
CREATE TABLE matchup_stats (
  champion_id  INTEGER NOT NULL,
  role         TEXT NOT NULL,
  opp_id       INTEGER NOT NULL,
  games        INTEGER NOT NULL,
  wins         INTEGER NOT NULL,
  tl_games     INTEGER NOT NULL,           -- denominador de los diffs y de las capas por rival
  gold_diff_15 REAL,                       -- medias sobre tl_games; NULL si tl_games = 0
  cs_diff_15   REAL,
  PRIMARY KEY (champion_id, role, opp_id)
) WITHOUT ROWID;

CREATE TABLE synergy_stats (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  ally_id     INTEGER NOT NULL,
  ally_role   TEXT NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, ally_id, ally_role)
) WITHOUT ROWID;

CREATE TABLE vs_team_stats (               -- contra un campeón rival en cualquier rol
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  enemy_id    INTEGER NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_id)
) WITHOUT ROWID;

-- Loadouts
CREATE TABLE rune_page_defs (              -- una fila por página normalizada distinta (§18.6)
  page_id       INTEGER NOT NULL PRIMARY KEY,
  primary_style INTEGER NOT NULL,
  sub_style     INTEGER NOT NULL,
  perk1         INTEGER NOT NULL,          -- keystone; perk1..perk4 de la primaria, en orden
  perk2         INTEGER NOT NULL,
  perk3         INTEGER NOT NULL,
  perk4         INTEGER NOT NULL,
  perk5         INTEGER NOT NULL,          -- secundarias, perk5 < perk6
  perk6         INTEGER NOT NULL,
  shard_offense INTEGER NOT NULL,          -- shards por posición, nunca reordenados
  shard_flex    INTEGER NOT NULL,
  shard_defense INTEGER NOT NULL
);

CREATE TABLE rune_pages (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  opp_id      INTEGER NOT NULL,            -- 0 = general
  page_id     INTEGER NOT NULL,            -- rune_page_defs
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, opp_id, page_id)
) WITHOUT ROWID;

CREATE TABLE rune_page_vs_profile (        -- página según el perfil del equipo rival
  champion_id   INTEGER NOT NULL,
  role          TEXT NOT NULL,
  enemy_profile TEXT NOT NULL,             -- valores de champ_vs_profile
  page_id       INTEGER NOT NULL,
  games         INTEGER NOT NULL,
  wins          INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_profile, page_id)
) WITHOUT ROWID;

CREATE TABLE item_builds (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  opp_id      INTEGER NOT NULL,            -- 0 = general
  layer       TEXT NOT NULL,               -- start | core | boots | fourth | fifth | sixth
  item1       INTEGER NOT NULL,            -- 0 = vacío. start: ordenados por id, con repetidos;
  item2       INTEGER NOT NULL,            -- core: en orden de compra; el resto usa solo item1
  item3       INTEGER NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, opp_id, layer, item1, item2, item3)
) WITHOUT ROWID;

CREATE TABLE item_vs_profile (             -- ítems finales según el perfil rival
  champion_id   INTEGER NOT NULL,
  role          TEXT NOT NULL,
  enemy_profile TEXT NOT NULL,             -- valores de champ_vs_profile + 'any' (línea base)
  item_id       INTEGER NOT NULL,
  games         INTEGER NOT NULL,          -- partidas que lo terminó en el inventario final
  wins          INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, enemy_profile, item_id)
) WITHOUT ROWID;

CREATE TABLE spell_pairs (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  opp_id      INTEGER NOT NULL,            -- 0 = general
  spell_a     INTEGER NOT NULL,            -- normalizado (a < b)
  spell_b     INTEGER NOT NULL,
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, opp_id, spell_a, spell_b)
) WITHOUT ROWID;

CREATE TABLE skill_orders (
  champion_id INTEGER NOT NULL,
  role        TEXT NOT NULL,
  max_order   TEXT NOT NULL,               -- 'QWE'; 4 letras si el kit sube la R como básica ('RQWE')
  sequence    TEXT NOT NULL,               -- secuencia más común de ese max_order, hasta 18 niveles
  games       INTEGER NOT NULL,
  wins        INTEGER NOT NULL,
  PRIMARY KEY (champion_id, role, max_order)
) WITHOUT ROWID;
```

**Claves de `meta`:**

| Clave | Valor |
|---|---|
| `schema_version` | Entero |
| `patch`, `queue`, `bracket` | `16.21`, `420`, `emerald_plus` / `diamond_plus` |
| `generated_at`, `ddragon_version` | ISO 8601, `16.21.1` |
| `matches` | Partidas del archivo, ya con la mezcla de §14.13. Denominador de pick y ban rate |
| `regions` | JSON. Las regiones siempre van mezcladas |
| `blend_patches`, `blend_k` | JSON con los parches mezclados (`["16.21","16.20"]`) y el `k` de §14.13 (0 sin mezcla) |
| `thresholds` | JSON. `[mínimo, confiable]` por tipo de dato (§18.2) |
| `priors` | JSON. Fuerza `m` del prior por tipo de dato y `p0` de (champ, role) (§18.1) |
| `tier_cutoffs` | JSON. Corte mínimo de `wr_smoothed(champ, role)` por tier; debajo de C es D |
| `profile_rules` | JSON. Reglas de perfil rival (§18.4) |

```json
{
  "thresholds": { "champ_role": [200, 1000], "matchup": [30, 300], "synergy": [50, 400],
                  "vs_team": [30, 300], "profile": [100, 500], "rune_page": [100, 800],
                  "build_layer": [100, 600], "item_vs_profile": [50, 300],
                  "spells": [100, 500], "skill_order": [100, 600] },
  "priors": { "champ_role": { "m": 100, "p0": 0.5 }, "relation": 200, "loadout": 500 },
  "tier_cutoffs": { "S": 0.53, "A": 0.515, "B": 0.50, "C": 0.485 },
  "profile_rules": { "min_champions": 3,
                     "heavy_ad": { "phys_share_weighted": 0.65 },
                     "heavy_ap": { "magic_share_weighted": 0.60 },
                     "heavy_cc": { "cc_score_mean": 0.60 },
                     "mixed":    { "not": ["heavy_ad", "heavy_ap"] } }
}
```

**Capas y denominadores.** Cada dato viene de una de dos fuentes:

- **Partida** (match-v5, todas las partidas): `champion_roles`, `champ_role_stats`,
  `champ_ban_stats`, `duration_curves`, `champ_vs_profile`, `matchup_stats.games`,
  `synergy_stats`, `vs_team_stats`, `rune_pages`, `rune_page_vs_profile`, `spell_pairs`,
  `item_vs_profile` y `champion_profiles` hasta `cc_score`.
- **Timeline** (muestra estratificada, §14.5): `item_builds`, `skill_orders`,
  `matchup_stats.gold_diff_15` y `cs_diff_15`, y `champion_profiles` desde `tl_games`.
  Excepción: si un (champ, role) tiene `tl_games` por debajo del mínimo de `build_layer`, su
  core y sus botas generales salen de ítems finales (§14.12) y usan el denominador de partida.

Denominador de cada regla "uso ≥ X %" dentro de un contexto:

| Contexto | Datos de partida | Datos de timeline |
|---|---|---|
| General | `champ_role_stats.games` | `champion_profiles.tl_games` |
| vs rival de lane | `matchup_stats.games` | `matchup_stats.tl_games` |
| vs perfil rival | `champ_vs_profile.games` (`'any'`: `champ_role_stats.games`) | — (no hay capas por perfil) |

### Base personal (local, read-write, en la app)

```sql
CREATE TABLE my_matches (
  game_id INTEGER PRIMARY KEY, queue_id INTEGER, patch TEXT, played_at INTEGER,
  champion_id INTEGER, role TEXT, win INTEGER,
  kills INTEGER, deaths INTEGER, assists INTEGER, cs INTEGER, duration_s INTEGER,
  opp_champion_id INTEGER,
  spell1 INTEGER, spell2 INTEGER, perks TEXT, items TEXT
);

CREATE TABLE my_match_participants (    -- los otros 9, para insights por perfil o sinergia
  game_id INTEGER NOT NULL, slot INTEGER NOT NULL,   -- slot: orden 0–8 en la partida
  champion_id INTEGER NOT NULL, is_enemy INTEGER NOT NULL, role TEXT,
  PRIMARY KEY (game_id, slot)            -- blind pick y One for All repiten campeones
);

CREATE TABLE champion_overrides (       -- preferencias manuales del usuario
  champion_id INTEGER, role TEXT,
  runes_mode TEXT, fixed_page TEXT,     -- JSON
  spells_mode TEXT, fixed_spells TEXT,
  items_mode TEXT, fixed_items TEXT,    -- JSON del ItemSet fijo (§21.5 "set fijo")
  favorite INTEGER, banned_from_pool INTEGER,
  PRIMARY KEY (champion_id, role)
);

CREATE TABLE pool (                     -- pool declarado por rol
  role TEXT, champion_id INTEGER, priority INTEGER,
  PRIMARY KEY (role, champion_id)
);

CREATE TABLE import_log (
  ts INTEGER, game_id INTEGER, champion_id INTEGER, what TEXT, result TEXT, detail TEXT
);
```

Decisiones de la base personal:

- La maestría no se guarda: se lee en vivo de la LCU (§19.1) cuando hace falta.
- `played_at` y `ts` son epoch en milisegundos (el `gameCreation` de la LCU).
- Si `banned_from_pool` de un override y `pool` no coinciden, gana `banned_from_pool`: una
  exclusión explícita pesa más que la lista del pool.
- Vive en `~/Library/Application Support/<bundle id>/personal.sqlite`, así Debug y Release no
  la comparten (§24). Las migraciones son de GRDB (`DatabaseMigrator`) desde `v1`; una
  migración publicada nunca se edita, se agrega otra.
- `perks` e `items` son arrays JSON de enteros en el orden del cliente (`[8112,8139,…]`).
- `fixed_page` es JSON de la `RunePage`:
  `{"perks":[…],"primaryStyle":8100,"subStyle":8200}`.
- `fixed_spells` es un array JSON de dos IDs en el orden de la `SpellPair` (`[4,14]`).
- `fixed_items` es JSON del `ItemSet`:
  `{"blocks":[{"items":[{"count":1,"id":1056}],"title":"…"}]}`.
- Las claves JSON van ordenadas; un campo fijo sin valor es `NULL`.
- `role`, `runes_mode`, `spells_mode`, `items_mode`, `what` y `result` guardan el `rawValue`
  de los enums de MitoCore (`MIDDLE`, `fixed_set`, `applied`…). Un modo, parte o resultado
  desconocido carga como `.unknown` sin error; un rol desconocido o un JSON que no decodifica
  es un error de lectura.
- `win`, `is_enemy`, `favorite` y `banned_from_pool` son 0/1. `slot` es el índice en
  `MyMatch.participants`, y los participantes se leen ordenados por `slot`.
- "Borrar mis datos" (§25) vacía las cinco tablas en una sola transacción: o se borra todo o
  no se borra nada.

---

## 18. Motor de recomendaciones

### 18.1 Fundamentos estadísticos

**Suavizado bayesiano del winrate.** Nunca se usa el winrate crudo con muestras chicas.

```
wr_smoothed = (wins + α) / (games + α + β)
con prior centrado en el winrate base del contexto:
α = m · p0,  β = m · (1 − p0)
p0 = winrate base: 0,5 para (champ, role); wr_smoothed(champ, role) para todo lo demás
m  = fuerza del prior (en partidas): 100 para (champ, role); 200 para relaciones (matchup,
     sinergia, vs_team, perfil rival); 500 para loadouts (runas, ítems, spells, habilidades,
     incluidos los ítems de `item_vs_profile`: es una elección de ítem, no una relación)
```

Los valores viven en `meta.priors`. El tier (S–D) de la tier list sale de
`wr_smoothed(champ, role)` con los cortes de `meta.tier_cutoffs`.

**Delta contra la línea base.** Para matchups y sinergias se usa la **diferencia** respecto
del winrate general del campeón, no el valor absoluto:

```
matchup_delta(A vs B) = wr_smoothed(A vs B) − wr_smoothed(A)
```

Así un campeón con winrate general alto no domina todas las listas solo por eso.

**Intervalo de confianza.** Para mostrar en la UI y ordenar con cautela se usa el límite
inferior de Wilson al 90 %. Las recomendaciones con poca muestra se marcan con un ícono de
"muestra baja".

El intervalo de Wilson es bilateral al 90 % (`z ≈ 1,645`, cuantil 0,95 de la normal) y se
calcula sobre los conteos crudos (`wins`, `games`), no sobre el winrate suavizado. Sin
partidas el intervalo es `[0, 1]`.

**Backoff jerárquico.** Cada consulta busca del contexto más específico al más general y se
queda con el primero que supera la muestra mínima. Si hay varios, los mezcla ponderando por
muestra:

```
(champ, role, opp)          en la capa diamond_plus, si está activada
  → (champ, role, opp)      en el archivo base emerald_plus
  → (champ, role, perfil rival)
  → (champ, role)
```

El parche anterior no es un nivel del backoff: la mezcla ya viene en el archivo (§14.13).

### 18.2 Umbrales de muestra mínima (iniciales, ajustables)

| Dato | Clave en `meta.thresholds` | Mínimo para usar | Mínimo para "confiable" |
|---|---|---|---|
| champ+role | `champ_role` | 200 | 1.000 |
| matchup | `matchup` | 30 | 300 |
| sinergia | `synergy` | 50 | 400 |
| vs_team | `vs_team` | 30 | 300 |
| perfil rival | `profile` | 100 | 500 |
| página de runas | `rune_page` | 100 | 800 |
| capa de build | `build_layer` | 100 | 600 |
| ítem vs perfil | `item_vs_profile` | 50 | 300 |
| spells | `spells` | 100 | 500 |
| orden de habilidades | `skill_order` | 100 | 600 |

El exporter filtra con estos valores y los escribe en `meta.thresholds`; la app lee los mismos.

Ambos mínimos son inclusivos: debajo del mínimo para usar el dato no se usa; desde ese mínimo
y hasta antes del de "confiable" se usa con la marca de "muestra baja"; desde el de "confiable"
va sin marca. Un (champ, role) debajo del mínimo de `champ_role` no tiene tier.

### 18.3 Score de pick

Para cada campeón candidato `c` en tu rol `r`:

```
score(c) =  w_meta    · meta(c, r)
          + w_matchup · matchup(c, r, rival_de_lane)
          + w_counter · Σ vs_team(c, r, e) para los rivales e ya lockeados (excepto el de lane)
          + w_synergy · Σ synergy(c, r, a, rol_a) para los aliados a ya lockeados
          + w_comp    · comp_fit(c, equipo_aliado, equipo_rival)
          + w_personal· personal(c, r)
          − penalties(c)
```

Componentes (todos en "puntos de winrate" para que sean comparables):

- `meta`: `wr_smoothed(c, r) − 0,5`
- `matchup`: delta contra el rival de lane, mezclado por probabilidad de rol si es inferido
- `vs_team`: deltas contra el resto de los rivales, con peso reducido (0,3)
- `synergy`: deltas con aliados. Peso alto para pares fuertes (bot + support, jungla + mid)
- `comp_fit`: equilibrio de la composición (ver 18.4)
- `personal`: ver sección 19
- `penalties`: no lo tenés (si el modo es "solo mi pool"), está baneado o pickeado, o tiene
  muestra demasiado baja

Pesos iniciales:

| Peso | Default | Notas |
|---|---|---|
| `w_meta` | 1,0 | |
| `w_matchup` | 1,2 | Se anula si el rival de lane no se conoce |
| `w_counter` | 0,3 | |
| `w_synergy` | 0,6 | |
| `w_comp` | 0,8 | |
| `w_personal` | 1,0 | Se ajusta con el slider "Meta ↔ Comfort" |

**Slider "Meta ↔ Comfort"** en Settings y en la ventana de champ select: mueve `w_personal`
entre 0,2 y 2,5 y compensa `w_meta`. Con `s ∈ [0, 1]` (0 = Meta, 1 = Comfort; fuera del rango
se recorta), guardado en `ChampSelectSettings.metaComfortBalance` con default 0,5:

```
w_personal(s) = 0,2 + 1,6 · s           si s ≤ 0,5
              = 1,0 + 3,0 · (s − 0,5)   si s > 0,5
w_meta(s)     = 1,5 − s
```

`w_personal` es lineal por tramos para que el default del setting (0,5) dé exactamente los
pesos de la tabla (1,0 y 1,0); una sola recta de 0,2 a 2,5 pondría el default en `s ≈ 0,35`.
`w_meta` baja de 1,5 a 0,5: siempre positivo, así el meta nunca deja de contar. Los demás
pesos no se mueven. `PickWeights(metaComfortBalance:)` en `MitoEngine/Pick/PersonalPoints`.

**Modos de candidatos:**

- "Mi pool": solo campeones del pool declarado o con al menos N partidas propias.
- "Campeones que tengo": todo lo que poseés.
- "Todos": incluye campeones que no tenés (útil para aprender o comprar).

En la app (`Features/ChampSelect/DraftRecommendations`): el pool es el declarado para tu rol,
por prioridad, más los campeones con **N = 5** partidas propias o más en ese rol (de cualquier
cola), por partidas; un override que lo excluye del pool lo saca por las dos vías (§17). El
mismo orden es el `myPicks` del score de ban (§18.5). "Lo que tenés" es el `pickableChampionIDs`
del champ select: la LCU no tiene un endpoint de campeones propios que usemos, y el pickable ya
incluye los tuyos más la rotación gratuita. Si ese pedido falla queda vacío, y "Campeones que
tengo" y "Mi pool" no muestran candidatos.

**Salida:** el top 10 con score, desglose por componente y 2–3 razones en texto.

```swift
struct PickRecommendation: Sendable, Identifiable {
    let id: ChampionID
    let score: Double
    let breakdown: [ScoreComponent: Double]
    let reasons: [Reason]          // ordenadas por impacto
    let confidence: SampleLevel    // nivel de muestra del (champ, role) del candidato (§18.2)
}

struct Reason: Sendable {          // MitoCore/Recommendation/Reason.swift
    let kind: Kind
    let sample: SampleLevel?       // "muestra baja" va acá, no como razón aparte
    enum Kind {
        case matchup(opponent:delta:games:)          // el signo del delta da fuerte o débil
        case profileMatchup(opponent:profiles:delta:games:)   // backoff del matchup al perfil rival
        case versusEnemy(enemy:delta:games:)
        case synergy(ally:allyRole:delta:games:)
        case meta(tier:games:)
        case comfort(poolRank:games:winrate:)        // §19.3: "Tu 3er campeón (41 partidas, 56 %)"
        case fillsDamageGap(adds:alliedShare:), addsFrontline(tankiness:),
             addsCrowdControl(ccScore:), addsEngage, powerCurve(early:teamEarly:)   // §18.4
        case threatens(pick:delta:games:)                                         // §18.5
        case generalChoice(part:usage:winrate:games:), adaptedToOpponent(part:opponent:games:),
             adaptedToProfile(part:profile:games:)                                // §18.6–18.9
        case countersFlag(item:flag:enemies:),
             situationalItem(item:profile:buyRate:baselineBuyRate:winrateDelta:)  // §18.7
    }
}
```

Los deltas y shares van como fracción; la UI los formatea. `profileMatchup` es el backoff del
matchup (abajo): `profiles` son las etiquetas activas con fila usable de `champ_vs_profile`,
`delta` su media ponderada por `games` y `games` la suma; así la UI lo muestra como estimado
por perfil ("vs Zed (estimado por perfil: mucho AD)") y no como un matchup directo. `comfort`
es la comodidad personal: partidas propias con el campeón en ese rol, su winrate crudo y
`poolRank`, el puesto (desde 1) en el orden del pool del rol, `nil` fuera de él. El motor
emite los dos y la app los muestra con su propio texto (`ReasonRow`, §22.3).

Precisiones (`MitoEngine/Pick/PickScoring`):

- Cada delta es `matchup_delta` de §18.1 contra el `wr_smoothed(c, r)` del candidato, con la
  fila de `matchup_stats`, `vs_team_stats` o `synergy_stats` desde su mínimo (§18.2); debajo
  del mínimo o sin fila ese término vale 0, salvo el matchup, que hace backoff (abajo).
- Backoff del matchup (§18.1): si contra un rival con `p(e) > 0` no hay fila de
  `matchup_stats` desde su mínimo, su delta es el del perfil del equipo rival
  (`Composition.enemyProfile`, §18.4) contra el candidato: el `matchup_delta` de cada etiqueta
  activa con fila de `champ_vs_profile` desde el mínimo de `profile`, y con varias etiquetas su
  media ponderada por `games`. Entra igual que un matchup, `p(e) · delta` con `w_matchup`. Sin
  perfil rival (menos de `min_champions` perfilados o sin `profile_rules`) o sin filas usables
  cae a `(champ, role)`, delta 0. La razón es `profileMatchup` contra ese rival, con las
  etiquetas que tuvieron fila usable (por valor crudo), la suma de sus `games` y el nivel de
  muestra más bajo entre ellas (las etiquetas comparten partidas, así que la suma no se toma
  como muestra); con fila directa de `matchup_stats` es `matchup`. `vs_team` y sinergia no
  hacen backoff.
- Rival de lane: un rival lockeado con rol se toma en ese rol; los demás lockeados se infieren
  (§12.3) entre los roles que ningún slot rival tiene. `p(e)` es la probabilidad de que `e`
  juegue tu rol (1 o 0 con rol, `roleProbabilities` si no). `matchup = Σ p(e) · delta(c vs e)`
  y `vs_team = Σ (1 − p(e)) · delta_vs_team(c, e)` sobre los rivales lockeados: cada rival
  cuenta como lane o como resto del equipo según su probabilidad. Sin ningún rival con
  probabilidad en tu rol, el matchup vale 0.
- Sinergia: los aliados lockeados sin tu slot, en su rol asignado o inferido (como en §18.4).
  Un par fuerte (bottom + utility, jungle + middle, en cualquier orden) cuenta ×1,5 dentro de
  la suma.
- `comp_fit` es el valor de §18.4 antes de `w_comp`; `personal` llega como función
  `(campeón, rol) → PersonalTerm?` que pasa quien llama: los puntos de winrate de
  `PersonalPoints.points` (§19.3), las partidas y victorias propias con el campeón en ese rol y
  su `poolRank`. `PersonalTerm(_:poolRank:)` lo arma desde un `PersonalScore`; la app pasa el
  puesto en el pool del rol que arma para "Mi pool" (arriba). Sin datos es 0.
- Candidatos: los campeones con fila de `champ_role_stats` en tu rol desde el mínimo de
  `champ_role`; debajo del mínimo no se rankean (como en §18.5), así que `penalties` siempre
  vale 0 y se guarda en el desglose. "Mi pool" es pool ∩ campeones que tenés, "Campeones que
  tengo" es lo que tenés y "Todos" no filtra; el pool y lo que tenés son entradas. Nunca se
  rankea lo baneado ni lo lockeado por cualquier equipo; los hovers sí.
- Razones: una por cada término con fila usable (matchup, vs_team y sinergia por campeón, el
  tier del candidato y las de comp fit), ordenadas por el valor absoluto de su aporte
  ponderado al score; a igual aporte, primero los rivales en orden de draft (matchup y después
  vs_team), luego los aliados, el tier, el comp fit y la comodidad. Cada una lleva el nivel de
  muestra de su fila.
- Comodidad: una razón `comfort` cuando `personal` no es 0 y hay partidas propias con el
  candidato en ese rol, con su winrate crudo (`wins / games`) y su `poolRank`. Su aporte es
  `w_personal · personal` y no lleva muestra (no es una fila del snapshot).
- Orden por score descendente y, a igualdad, por `champion_id`; top 10 por defecto.

### 18.4 Comp fit

Perfil de cada equipo a partir de `champion_profiles` de los lockeados, con el daño
ponderado por volumen:

```
team_phys  = Σ(phys_share · dmg_per_min) / Σ dmg_per_min
team_magic = Σ(magic_share · dmg_per_min) / Σ dmg_per_min
team_tank  = suma de tankiness
team_cc    = suma de cc_score
team_early = media de early_strength
early_strength(c, r) = wr_s de los buckets hasta 25 min (<20, 20-25) − winrate de la curva
late_strength(c, r)  = wr_s de los buckets desde 35 min (35-40, 40+) − winrate de la curva
                       (duration_curves)
```

**Perfil rival.** Con 3 o más lockeados, el equipo rival se clasifica con `meta.profile_rules`
(§17): `heavy_ad` y `heavy_ap` por el share ponderado, `heavy_cc` por la media de `cc_score` y
`mixed` cuando no es ni `heavy_ad` ni `heavy_ap`. Es multi-label: un equipo puede ser
`heavy_ad` y `heavy_cc` a la vez, y el pipeline clasifica cada partida con las mismas reglas
(§14.10). `poke` no es un perfil sino un flag de `champion_flags`.

Reglas (cada una da un bonus o penalidad en puntos de winrate):

- **Balance de daño:** si `team_phys > 0,7` con 3 o más lockeados, bonus a candidatos con
  `magic_share` alto, y viceversa.
- **Frontline:** si el equipo no tiene a nadie con `tankiness` en el top 30 %, bonus a
  candidatos tanqueros (sobre todo en top, jungla y support).
- **CC / engage:** bonus a candidatos con CC o con el flag `engage` si `team_cc` es bajo y
  nadie del equipo tiene `engage`.
- **Curva de poder:** leve bonus a la coherencia (equipo early con campeón early) o una
  advertencia si la mezcla es mala.

Los bonus son chicos (±0,5 a ±2 puntos) y se calibran comparando contra el winrate real de
composiciones en los datos (v1.5: aprender los pesos con una regresión logística sobre
features de composición).

Decisiones del comp fit (`Composition` en `MitoEngine/Composition/`):

- Los miembros de un equipo son los lockeados, cada uno en su rol asignado o, sin rol, en el
  inferido entre los lockeados sin rol (§12.3). Un lockeado sin `champion_profiles` en ese
  rol no cuenta para el perfil ni para el mínimo, igual que en el pipeline. Si el daño total
  de los perfilados es 0, `team_phys` y `team_magic` valen 0.
- Perfil rival: los umbrales de `profile_rules` son mínimos inclusivos, `min_champions` cuenta
  perfilados y `mixed` es "ninguno de `mixed.not`". Sin `profile_rules` o con menos perfilados
  que el mínimo, el equipo no tiene perfil.
- Ninguna regla aplica con menos de 3 aliados perfilados (sin contar el slot propio): con el
  equipo vacío el comp fit es 0.
- Balance de daño: estricto `> 0,7`; "share alto" del candidato es `≥ 0,5` del tipo que falta.
- Frontline y CC: "top 30 %" es `tankiness` o `cc_score` `≥ 0,7`. El equipo no tiene
  frontline si ningún perfilado llega a 0,7; su CC es bajo si la media de `cc_score` es
  `< 0,5` (la mediana del rol), es decir `team_cc < 0,5 · perfilados`. `engage` cuenta en
  cualquier lockeado, tenga perfil o no.
- Bonus iniciales: balance de daño +1,5; frontline +1,5 en top, jungla y support y +0,75 en
  otro rol; CC +1; `engage` +1; curva de poder +0,5. CC y `engage` suman por separado. Por
  ahora no hay penalidades.
- Curva de poder (`PowerCurve`): el winrate de la curva es Σ `wins` / Σ `games` de todos sus
  buckets, no `wr_smoothed(champ, role)`, así los segmentos se miden contra las mismas
  partidas (en el fixture los buckets no suman `champ_role_stats.wins`; mito-data lo corrige).
  Cada segmento se suaviza con el prior de relaciones (§18.1) centrado en ese total: un
  segmento sin partidas vale 0 y una curva sin partidas no tiene fuerza. `team_early` es la
  media de `early_strength` de los aliados con curva, y la regla necesita 3 o más.
- Regla de la curva: el equipo es early con `team_early ≥ 0,005` y late con
  `team_early ≤ −0,005` (es una media, así que el corte es la mitad del del candidato); el
  candidato comparte la curva con `early_strength ≥ 0,01` en un equipo early o
  `late_strength ≥ 0,01` en uno late. Todos inclusivos. Da el bonus a la coherencia; la
  advertencia por mala mezcla no está, porque no hay penalidades. La razón es
  `powerCurve(early:teamEarly:)` con el `early_strength` del candidato y `team_early`.
- Las razones de perfil llevan el nivel de muestra `champ_role` del candidato; `powerCurve`,
  el nivel `champ_role` de las partidas de la curva del candidato; `addsEngage` no lleva
  muestra (es un flag). Van de mayor a menor bonus y, a igual bonus, en el orden de
  las reglas de arriba.

### 18.5 Score de ban

Para el jugador en su rol:

```
ban_score(e) =  presencia(e) · amenaza(e)
presencia(e) = probabilidad de que e termine en tu lane o en el equipo rival
             ≈ pick_rate(e, tu_rol) · (1 − ban_rate(e)) + λ · pick_rate_global(e)
pick_rate(e, r)     = champ_role_stats.games(e, r) / meta.matches
pick_rate_global(e) = Σ_r champ_role_stats.games(e, r) / meta.matches
ban_rate(e)         = champ_ban_stats.bans(e) / meta.matches
amenaza(e)   = media ponderada de −matchup_delta(c, tu_rol, e) sobre tus campeones
               probables c (top 3 de tu pool), más wr_meta(e) − 0,5
```

Reglas:

- Nunca recomendar banear lo que un aliado tiene en hover.
- Nunca recomendar banear un campeón de tu propio pool principal.
- Mostrar el top 5 con la razón ("Malzahar: −4,2 % para tu Ahri y −3,1 % para tu Syndra").

Precisiones (`MitoEngine/Ban/BanScoring`):

- `λ = 0,3`, el mismo peso reducido que `w_counter` (§18.3) para lo que no es la lane.
- Candidatos: los campeones con fila de `champ_role_stats` en tu rol desde el mínimo de
  `champ_role`; la `confidence` es ese nivel. `wr_meta(e) = wr_smoothed(e, tu_rol)`. Los
  pick rates usan los conteos crudos, sin umbral; un campeón sin fila en `champ_ban_stats`
  tiene `ban_rate = 0`.
- Tus campeones probables son los 3 primeros de tu pool del rol, en orden de prioridad; la
  app lo pasa como entrada. La media pondera por `matchup_stats.games` (como el backoff de
  §18.1) y solo usa los matchups desde el mínimo de `matchup`; sin ninguno ese término vale 0.
- Exclusiones: lo baneado, lo lockeado o en hover de cualquier aliado (vos incluido), lo
  lockeado por el rival y todo tu pool del rol, no solo los 3 primeros. Lo que no podés
  pickear sí se puede recomendar: banear no exige tenerlo.
- Razones: un `threatens` por cada campeón probable con delta negativo, del más amenazado al
  menos, con el nivel de muestra del matchup; después el tier del candidato. `amenaza` puede
  ser negativa: ese candidato queda debajo de los que tienen `ban_score` positivo.
- Orden por `ban_score` descendente y, a igualdad, por `champion_id`.

### 18.6 Runas

**Loadout general implementado (P6-04, `LoadoutSelection.general` en `MitoEngine/Loadout`).**
Reglas comunes a §18.6–§18.9, solo `opp_id = 0`:

- `wr_s` de cada fila es `priors.loadoutWinrate` centrado en `wr_smoothed(champ, role)`. "Buen
  winrate" es `wr_s ≥ wr_smoothed(champ, role)`.
- Una fila se considera solo si pasa el mínimo de su tipo (`rune_page`, `spells`,
  `build_layer`, `skill_order`). Si ninguna cumple la regla de la parte, se elige la más
  jugada de todas (la que §14.12 deja sola) y queda marcada.
- Cada parte lleva su `SampleLevel` según las partidas de la fila elegida. Si el (champ, role)
  está debajo del mínimo de `champ_role`, se elige igual pero todas las partes quedan
  `.belowMinimum`. Sin umbral para el tipo en `meta`, la parte es `.usable`.
- Sin `meta` o sin fila de `champ_role_stats`, el loadout va vacío. Una parte sin candidatas
  es `nil`.
- Desempates, en orden: el criterio secundario (partidas si se ordena por `wr_s`, `wr_s` si se
  ordena por partidas) y después el contenido de la fila, menor primero (ids de estilos y
  perks, de spells, de ítems; Q < W < E < R en el skill order). No depende del orden en que
  lleguen las filas.

Runas: la página con mayor `wr_s` entre las de uso ≥ 5 % de `champ_role_stats.games`
(inclusivo). Una página sin exactamente 9 perks nunca se elige; si no queda ninguna, no hay
runas.

1. Candidatas: `rune_pages` del (champ, role) con `opp_id = 0`, con backoff. El contenido de
   cada página sale de `rune_page_defs` por `page_id`.
2. Si el rival de lane es conocido y `rune_pages` con ese `opp_id` tiene muestra, se mezcla:
   `score(page) = wr_s(page | opp) · w_opp + wr_s(page | general) · (1 − w_opp)`, con
   `w_opp = n_opp / (n_opp + 300)`.
3. Perfil rival (por ejemplo, `heavy_ap`): ajuste con `rune_page_vs_profile`, sobre todo en
   shards y runas defensivas de la rama Valor. Con varios perfiles activos se promedian sus
   ajustes.
4. Se elige la página con mayor score **entre las que tienen uso ≥ 5 %** dentro del
   contexto. Así se evitan páginas raras que ganan por ruido. Denominador: general,
   `champ_role_stats.games`; vs rival, `matchup_stats.games`; vs perfil,
   `champ_vs_profile.games`.
5. Explicación: "Electrocutar (58 % de uso, 53,9 % WR). vs Zed: Segunda Piel en vez de
   Cosecha".

**Normalización de página:** solo se normaliza el orden de los perks secundarios (ascendente)
para agrupar páginas equivalentes. Los shards son posicionales (ofensa, flex, defensa) y nunca
se reordenan. Cada página distinta es una fila de `rune_page_defs`.

**Adaptado implementado (P7-06, `LoadoutSelection.adapted` en `MitoEngine/Loadout`).** Entrada:
el rival de lane (opcional), el perfil rival (`Set<EnemyProfile>`, el de
`Composition.enemyProfile`, §18.4) y los rivales lockeados (para los flags de §18.7). Sin
nada a qué adaptarse devuelve exactamente lo mismo que `general`. Reglas comunes a
§18.6–§18.8:

- **Backoff sin mezcla.** Cada parte se queda con el primer contexto en el que alguna fila
  pasa el mínimo de su tipo y la regla de uso de la parte, en el orden de §18.1: rival de lane
  → perfil rival → general. La mezcla ponderada de los pasos 2 y 3 de arriba (`w_opp`) no se
  implementa: un contexto adaptado gana entero o no se usa. Solo el general conserva el
  fallback a la fila más jugada (§14.12); un contexto adaptado sin fila que pase cae al
  siguiente. La capa `diamond_plus` no está en esta fase.
- El rival cuenta solo si tiene fila en `matchup_stats` (es el denominador). `wr_s` de cada
  fila sigue centrado en `wr_smoothed(champ, role)`, igual que en el general.
- Cada parte adaptada suma su razón (`adaptedToOpponent` o `adaptedToProfile`) con las
  partidas de la fila elegida y su `SampleLevel`; ese mismo nivel es el de la parte en
  `sampleLevels`. Las partes que caen al general no llevan razón. El skill order es siempre
  general (§18.9).
- Razones en orden: runas, spells, capas de ítems en orden de bloque, flags y situacionales.

Runas adaptadas: vs rival, las de `rune_pages` con ese `opp_id`, uso ≥ 5 % de
`matchup_stats.games`. Si no, las de `rune_page_vs_profile`: con varios perfiles activos se
**suman** partidas y victorias por página y el denominador es la suma de sus
`champ_vs_profile.games` (es el "se promedian sus ajustes" del paso 3, ponderado por muestra);
un perfil sin fila en `champ_vs_profile` no cuenta. Lleva un `adaptedToProfile` por perfil
que tenga la página elegida, con sus partidas.

### 18.7 Items

- Las capas salen de `item_builds` (timeline): el "uso ≥ X %" se mide contra
  `champion_profiles.tl_games` en general y `matchup_stats.tl_games` vs rival (§17).
- **Inicio:** el más ganador con uso ≥ 10 % para (champ, role, opp). Backoff a general.
- **Core (3 ítems):** el combo ordenado más frecuente con buen winrate. Mostrar 1 principal
  y 1–2 alternativos.
- **Botas:** mezcla del general y de las botas tier 2 de `item_vs_profile` para el perfil
  rival (por ejemplo, Tabis vs `heavy_ad` con 2 o más `auto_attacker`, Mercurio vs
  `heavy_cc` o `heavy_ap`).
- **Situacionales:** desde `item_vs_profile`, los ítems cuyo `buy_rate` y winrate suben
  claramente contra ese perfil frente a la línea base `'any'`, con
  `buy_rate(perfil) = games / champ_vs_profile.games` y
  `buy_rate('any') = games / champ_role_stats.games`. Reglas con flags: antiheal
  (`item_classes.antiheal`) si el rival tiene 2 o más `high_heal`; Banshee vs 2 o más
  `point_click_cc`; Zhonya vs `heavy_ad`.
- Cada bloque del item set lleva el motivo en el título.

**General implementado (P6-04).** Un bloque por capa con elección, en el orden `start`, `core`,
`boots`, `fourth`, `fifth`, `sixth`. El título del bloque es el valor de
`item_builds.layer` (`"start"`, `"core"`, …): el motor no pone texto y la app lo reemplaza
por su copy (Inicio, Núcleo, …) y el motivo. Los repetidos del inicio van como un ítem con
`count`. Inicio, botas y 4.º–6.º usan la regla del inicio (mayor `wr_s` con uso ≥ 10 % de
`tl_games`); el core, el más jugado con buen winrate. Una capa nunca repite un ítem de una
capa anterior (se descartan esas filas). Si `tl_games` no llega al mínimo de `build_layer`,
core y botas son de ítems finales (§14.12) y su uso se mide contra `champ_role_stats.games`.
Los alternativos del core no están todavía.

**Adaptado implementado (P7-06).** Con las reglas comunes de §18.6:

- **Capas vs rival.** Cada capa prueba primero las filas de `item_builds` con ese `opp_id`
  (las que el export haya guardado; hoy `start`, `core` y `boots`), con la misma regla de la
  capa y el uso medido contra `matchup_stats.tl_games`. Si ninguna pasa, la capa general.
- **Señales por perfil.** Un ítem de `item_vs_profile` sube contra un perfil activo si su fila
  pasa el mínimo de `item_vs_profile`, `buy_rate(perfil) ≥ 10 %`,
  `buy_rate(perfil) ≥ 1,5 × buy_rate('any')` y `wr_s(perfil) > wr_s('any')` (los dos con el
  prior de loadout; sin fila `'any'` su buy rate es 0 y su `wr_s` es la línea base). Se
  ordenan por `buy_rate(perfil) / buy_rate('any')` de mayor a menor, después por delta de
  winrate e id. Un ítem que sube contra dos perfiles cuenta una vez, con el más fuerte. En el
  fixture: 3047 ×3 y 3157 ×2,5 vs `heavy_ad`, 3075 ×2 vs `heavy_ad`, 3111 ×2,5 vs `heavy_ap`
  y ×3 vs `heavy_cc`.
- **Botas.** Si las botas no salieron del rival, la señal más fuerte que sea botas tier 2
  reemplaza a las generales, con `adaptedToProfile` y el nivel de `item_vs_profile`. Las
  otras botas que suben no se agregan en ningún bloque.
- **Bloque `situational`.** Después de las capas, un bloque titulado `situational` (la app
  pone el copy): primero los flags y después las demás señales, cada una con
  `situationalItem` (buy rates, delta de `wr_s` y nivel). Tabis vs `auto_attacker` y Zhonya vs
  `heavy_ad` no son reglas fijas: salen de las señales. Este bloque no tiene `SampleLevel` en
  `sampleLevels`; lo llevan sus razones.
- **Flags.** Con 2 o más rivales lockeados con `high_heal`, el antiheal que el campeón termina
  más seguido en la línea base `'any'` (desde el mínimo de `item_vs_profile`); con 2 o más
  `point_click_cc`, Banshee (3102) si el campeón la termina. Si la build ya tiene un ítem de la
  regla, no se agrega nada. Razón `countersFlag` sin muestra.
- **Sin repetidos.** Ninguna capa, flag ni señal repite un ítem ya elegido.
- **Clases de ítems.** Las botas tier 2 son los ítems con `itemClass(of:) == .bootsT2` y el
  antiheal los que marca `isAntiheal` (`item_classes`, §16.3); un ítem sin fila no es ni botas
  ni antiheal. Banshee (3102) para `point_click_cc` es una regla por ítem, no una clase.

### 18.8 Spells

- Par más ganador con uso ≥ 10 % para (champ, role, opp), con backoff. Denominador:
  `champ_role_stats.games` en general, `matchup_stats.games` vs rival.
- Reglas de seguridad: Smite obligatorio en jungla. Nunca sacar Flash salvo que el campeón
  tenga un par alternativo dominante (≥ 60 % de uso).
- Respetar la posición de Flash del usuario (D/F).

**General implementado (P6-04).** En jungla solo cuentan los pares con Smite (11); si no hay
ninguno, no hay spells. Si algún par tiene Flash (4), los pares sin Flash cuentan solo con
uso ≥ 60 % (inclusivo); si ninguno tiene Flash, cuentan todos. Entre los que quedan, la regla
del uso ≥ 10 %. El par sale en orden neutro (`spellA < spellB`); la posición de Flash la
decide el importador (§13.3).

**Adaptado implementado (P7-06).** Vs rival, los pares de `spell_pairs` con ese `opp_id`, con
las mismas reglas de Smite y Flash y uso medido contra `matchup_stats.games` (también el 60 %
de dominancia). Si ninguno pasa, el par general. No hay capa por perfil (no hay tabla).

### 18.9 Orden de habilidades

- El `max_order` de `skill_orders` más jugado con buen winrate (uso medido contra
  `champion_profiles.tl_games`), con su `sequence`. Al no haber un corte de uso, el
  denominador no cambia la elección (P6-04).
- La UI y el bloque de texto del item set muestran la prioridad de maxeo y los primeros 6
  niveles; la pestaña Build muestra la secuencia completa.

### 18.10 Rendimiento

- Al entrar en champ select se cargan en memoria (diccionarios) las filas relevantes para
  los campeones del rol y para los rivales y aliados a medida que aparecen.
- El recálculo completo tiene que tardar menos de 50 ms en un M1 con unos 170 campeones.
- `MitoEngine` es síncrono y puro. Se llama desde un `Task.detached` con prioridad
  `.userInitiated`.

---

## 19. Capa personal

### 19.1 Fuentes

1. **LCU match history** (sin API key): últimas partidas del usuario. Se sincroniza al
   abrir Mito y después de cada partida (`EndOfGame`). `ProfileModel` sincroniza en cada
   entrada a `connected` y en cada cambio de fase de gameflow hacia `EndOfGame`, una
   sincronización a la vez (un disparo que llega a mitad de una deja una más pendiente).
   Lee `currentSummoner` para la PUUID; sin ella no sincroniza. La PUUID solo arma la
   decodificación en memoria: no se guarda ni se loguea. La primera sincronización de cada
   ejecución pagina de a 20 hasta las últimas 100 partidas o hasta una página vacía; las
   siguientes leen solo la primera página. De las partidas que todavía no están guardadas,
   las incompletas (menos de 9 participantes más, o rol sin rival) piden la partida completa
   con `matchHistoryGame`, de a una; si ese pedido falla queda la versión de la lista. Una
   partida ya guardada no se vuelve a escribir, así que resincronizar no cambia nada. Se
   guardan todas las colas; quien lee filtra. El estado (`idle`, `syncing`,
   `synced(newGames:)`, `failed(.client | .storage)`) es el del último intento; una falla
   no reintenta sola, espera al próximo disparo.
2. **LCU champion mastery:** puntos y nivel por campeón.
3. **Pool declarado:** el usuario marca sus campeones por rol (onboarding).
4. **Opcional (v1.5):** historial profundo vía pipeline con la puuid del usuario (meses de
   partidas), consumido desde un endpoint propio o un archivo personal.

El historial y el pool se guardan en la base personal (§17) a través de `PersonalStore`
(§9.2). Cada partida guarda el campeón, el rol y el rival propios, y de los otros nueve solo
campeón, lado y rol: ningún identificador de jugador, ni siquiera el de la cuenta del usuario
(§5, §25). La posición de Flash sigue en los settings (§21.4).

### 19.2 Métricas por campeón y rol

```
my_games(c, r)
my_wr_smoothed(c, r)   = (wins + m·p_global) / (games + m)   con m = 15 y p_global = wr_s(c, r)
recency(c, r)          = Σ exp(−días_desde_partida / 30)
mastery_norm(c)        = log(1 + puntos) / log(1 + max_puntos)
kda_vs_avg(c, r)       = mi KDA / ((kills + assists) / max(1, deaths))   -- sumas de champ_role_stats
cs_vs_avg(c, r)        = mi CS/min / (cs / minutes)                       -- ídem
```

### 19.3 Score personal

```
personal(c, r) =  0,4 · (my_wr_smoothed − wr_s(c, r))      -- ¿lo juego mejor que el promedio?
                + 0,3 · comfort(c, r)                      -- familiaridad
                + 0,2 · in_pool(c, r)                      -- pool declarado
                + 0,1 · rendimiento relativo (kda_vs_avg, cs_vs_avg de 19.2)

comfort(c, r) = 0,6 · min(1, my_games / 30) + 0,4 · min(1, recency / 5)
                + 0,2 · mastery_norm   (con techo en 1)
```

Escalado a puntos de winrate: un comfort máximo vale unos +3 puntos, ajustable. Es
consistente con la evidencia de que jugar campeones con experiencia mejora el winrate.

Decisiones del score personal (`PersonalScoring` en `MitoEngine/Personal/`):

- Cuentan solo las partidas propias con ese campeón y ese rol; las que no tienen rol (ARAM)
  no cuentan para ningún rol. Qué colas entran lo decide quien llama.
- `wr_s(c, r)` es el `wr_smoothed(champ, role)` del snapshot (§18.1). Sin fila de
  `champ_role_stats` es el `p0` de `meta.priors`; sin snapshot abierto, 0,5.
- `recency`: una partida con fecha posterior a "ahora" (reloj desfasado) cuenta como jugada
  ahora, así ninguna vale más de 1.
- `mastery_norm`: `max_puntos` es el máximo entre los campeones del usuario; si es 0, la
  maestría normalizada es 0.
- "Mi KDA" y "mi CS/min" son agregados, con la misma forma que el promedio:
  `(Σkills + Σassists) / max(1, Σdeaths)` y `Σcs / Σminutos`. Un cociente sin datos de un
  lado (sin partidas propias, sin fila, `minutes` o el promedio en 0) vale 1: "como el
  promedio".
- `in_pool` vale 1 si el campeón está en el pool de ese rol y ningún override de ese
  (campeón, rol) lo excluye; la exclusión gana sobre el pool (§17).
- Rendimiento relativo = `clamp(((kda_vs_avg − 1) + (cs_vs_avg − 1)) / 2, −1, 1)`: 0 es
  jugar como el promedio.
- Sin partidas propias ni snapshot, todo componente está definido: `my_wr_smoothed = wr_s`,
  `recency = 0`, cocientes en 1, rendimiento relativo 0. Nunca hay NaN.
- El escalado no entra en la fórmula: `personal` se devuelve crudo, con cada componente.
  Para el score de pick (§18.3), `PersonalPoints.points(_:maxComfortWorth:)` en
  `MitoEngine/Pick/` lo pasa a puntos de winrate escalando solo los términos sin unidad:

  ```
  puntos = 0,4 · (my_wr_smoothed − wr_s)
         + (0,3 · comfort + 0,2 · in_pool + 0,1 · rendimiento relativo) · maxComfortWorth / 0,3
  ```

  El edge ya está en puntos de winrate y no se escala; el comfort al máximo (0,3 · 1) vale
  `maxComfortWorth`, por defecto 0,03. Sin datos personales vale 0.
  `PersonalScore.winratePoints(maxComfortWorth:)` implementa esta fórmula; la usan el pick
  score (vía `PersonalPoints`) y "Mi perfil".

### 19.4 Insights personales (para la UI)

- "Tu Ahri vs equipos de mucho AD: 7 partidas, 2 victorias. Considerá Zhonya antes". El
  equipo rival de cada partida sale de `my_match_participants` y se clasifica con
  `meta.profile_rules` del snapshot actual.
- "Ganás 61 % en partidas de menos de 25 minutos con Syndra: jugá agresivo early".
- "Tus 3 mejores matchups y tus 3 peores".
- Detección de tilt (opcional y suave): "Perdiste 4 seguidas". Sin moralina, como dato.

Decisiones de los insights (`ProfileInsights` en `Features/Profile/`, solo datos propios):

- Las partidas de menos de 5 minutos (remakes) no cuentan para ningún insight.
- **Matchups:** se agrupan por (campeón, rol, rival de lane) y entran desde 3 partidas. Los
  mejores son los de más de 50 % y los peores los de menos de 50 %, así un matchup nunca está
  en las dos listas; se muestran 3 de cada una. Desempate: más partidas, después un orden fijo
  por IDs.
- **Partidas cortas:** por campeón, partidas con rol de menos de 25 minutos contra las de 25 o
  más. Hacen falta 5 de cada lado y una diferencia de al menos 10 puntos de winrate; se
  muestra un solo insight, el del campeón con la diferencia más grande, con los dos winrates
  ("Ganás 62 % en partidas de menos de 25 minutos con Ahri, contra 44 % en las más largas").
- **Tilt:** las derrotas seguidas desde la partida más reciente, de cualquier cola; se muestra
  desde 3.
- **Muestra baja:** una fila de campeón, un matchup o un lado de las partidas cortas con menos
  de 10 partidas lleva la marca de "muestra baja" (§18.2).
- El insight por perfil rival ("vs equipos de mucho AD") espera a `meta.profile_rules` del
  snapshot de la Fase 7; hasta entonces no se muestra.

---

## 20. Pantalla de análisis pre-partida

Es el corazón de la v1. Se abre al entrar en champ select y se actualiza en vivo.

### 20.1 Layout (ventana principal, durante champ select)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Ranked Solo/Duo · Datos 16.21 · Esmeralda+           ⏱ 24s · Tu turno: PICK │
├───────────────┬───────────────────────────────────────────┬──────────────────┤
│ TU EQUIPO     │  RECOMENDADOS PARA VOS (MID)              │ EQUIPO RIVAL     │
│               │                                           │                  │
│ ▣ Garen  TOP  │  1. Ahri       +3,8   ████████▌  conf.alta│ ▣ Zed     MID?82%│
│ ▣ Vi     JG   │     · +2,1 vs Zed (8.212 partidas)        │ ▣ Darius  TOP 95%│
│ ▢ (vos)  MID  │     · Tu 3er campeón (41 partidas, 56 %)  │ ▢ ...            │
│ ▢ ...    ADC  │     · Tu equipo es 78 % AD → aporta AP    │ ▢ ...            │
│ ▢ ...    SUP  │  2. Syndra     +3,1   ███████             │ ▢ ...            │
│               │  3. Galio      +2,7   ██████              │                  │
│               │  [Meta ●────────○ Comfort]  [Mi pool ▾]   │                  │
├───────────────┴───────────────────────────────────────────┴──────────────────┤
│  ANÁLISIS                                                                    │
│  [Matchup] [Composición] [Build] [Mi historial]                              │
│                                                                              │
│  Matchup: Ahri vs Zed                                                        │
│  Winrate 52,3 % (±0,9)  ·  Oro @15: −85  ·  CS @15: +4                       │
│  Curva por duración: ▁▂▄▆▇▇  (Ahri escala mejor después del minuto 25)       │
│  Claves: guardar la E para cuando entra la R de Zed · Zhonya 2do ítem si...  │
│                                                                              │
│  Composición                                                                 │
│  Daño: Aliado ███████░░░ 78 % AD   Rival ████░░░░░░ 41 % AD                  │
│  Frontline: Aliado baja · Rival alta   CC: Aliado media · Rival alta         │
│                                                                              │
│  Loadout que se va a importar         [✓ Runas] [✓ Spells] [✓ Ítems]         │
│  Electrocutar · Sabor a sangre · ...  Flash/Ignite    Luden → Botas → ...    │
│                                              [Importar ahora]  [Editar]      │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Estado actual (Fase 7).** Durante champ select el destino "Ahora" muestra `ChampSelectView`
(el shell le pasa la vista a `NowView`, así Gameflow no depende de ChampSelect); fuera de champ
select, "Ahora" muestra la fase. `ChampSelectView` muestra el draft y las recomendaciones, todavía
sin el panel de análisis:

- Encabezado: cola, fase (Planificación, Bans y picks, Finalización), cuenta regresiva del timer
  y, si te toca, "Tu turno: elegir" o "Tu turno: banear". Todavía no muestra el parche de los
  datos. El `DraftContext` lleva el parche del cliente (`ClientDataModel.patch`, §9.3).
- Columnas "Tu equipo" y "Equipo rival" con una fila por celda: candado y nombre para un
  lockeado, mano y nombre en cursiva para un hover, "Sin campeón" si no hay ninguno; "(vos)" en
  tu celda; reloj de arena (pick) o señal de prohibido (ban) en las celdas que están jugando.
- Rol: los aliados muestran su posición asignada (TOP, JG, MID, ADC, SUP). Un rival inferido
  lleva "?" y su probabilidad ("MID? 82 %"); si la inferencia no tiene datos
  (`isUniformFallback`), muestra un ícono de pregunta, el rol en gris y "sin datos". Nunca se
  presenta como un hecho.
- La columna central "Recomendados para vos (MID)" lista el top 10 de `PickScoring` (§18.3),
  cada uno con su score como `DeltaBadge` ("+3,8"), un `WinrateBar` con el score contra 0, su
  `ConfidenceIndicator` y hasta 3 `ReasonRow` (§22.3). En la fila, VoiceOver lee el número y la
  muestra una sola vez, desde la barra. Mientras alguien banea (tu turno de ban o cualquier ban
  en curso) pasa a "Bans recomendados (MID)" con el top 5 de `BanScoring` (§18.5), sin badge ni
  barra: el `ban_score` no está en puntos de winrate. Son sugerencias: Mito no pickea ni banea
  (§5).
- Debajo de los picks, el slider "Meta ↔ Comfort" y el selector de candidatos (Mi pool /
  Campeones que tengo / Todos) escriben directo en `ChampSelectSettings` (§21.3), así que mueven
  también el setting.
- `ChampSelectModel.recommendations` se deriva al leerse del draft, los settings, el
  `StatsProvider` del snapshot abierto (`SnapshotModel.provider`) y los datos personales: un
  cambio de draft, de slider o de modo, o un snapshot que abre a mitad del draft, recalcula al
  instante. El cálculo es síncrono en el main actor: con el fixture tarda 0,04 ms y con un roster
  sintético de 170 campeones por rol, todas las relaciones y 100 partidas propias, 0,9 ms (picks)
  y 0,2 ms (bans), optimizado; en Debug, 10 ms. No hace falta sacarlo del main actor.
- Datos personales: con la primera sesión de cada champ select, junto con la cola y el
  pickable, lee una vez de la base personal el historial, el pool de cada rol y los overrides, y
  de la LCU la maestría (`championMastery`); se borran con el draft y una lectura que termina
  después se descarta como cualquier escritura vieja (§12.4). Un pedido que falla deja esa parte
  vacía. Con historial, `personal` es `PersonalPoints.points(PersonalScoring.score(…))` (§19.3);
  sin historial no hay término personal.
- En blind pick, arriba de la lista, un selector segmentado de rol (TOP, JG, MID, ADC, SUP)
  elige para qué rol recomendar (§20.3); con rol asignado no aparece.
- Estados vacíos de la columna: "Sin estadísticas todavía" sin snapshot (§20.3), "Sin rol
  asignado" en ARAM, "Recomendaciones apagadas" si el setting de picks o de bans
  está off, y "Ningún candidato" si el modo no deja pasar a nadie.
- Abajo, los bans por nombre.
- Solo campeones, roles y celdas: ningún nombre de jugador (§5). Cada fila es un solo elemento
  de VoiceOver con su rol, campeón, estado y turno.
- Fuera de champ select la vista no muestra nada. En la barra de menú,
  `RecommendationMenuSection` muestra una línea de resumen ("Champ select · tu turno de
  elegir", o "Champ select · N de M lockeados") y, debajo, la recomendación (§22.4); queda vacía
  fuera de champ select.
- La pestaña "Champ select" de Settings tiene "Mostrar la ventana al entrar en champ select"
  (`general.showWindowOnChampSelect`, §21.1). Con el setting on, cuando aparece el draft el shell
  abre la ventana principal en "Ahora", haya o no una ventana abierta (§9.3). Se abre una sola
  vez por champ select: un draft que se pierde y vuelve mientras la fase sigue en champ select
  no la reabre (si la cerraste, queda cerrada), y prender el setting a mitad de un champ select
  tampoco. Se rearma cuando no hay draft y la fase ya no es champ select. El shell solo pide la
  ventana: no llama a `NSApp.activate`.

### 20.2 Pestañas del análisis

1. **Matchup:** winrate suavizado con intervalo, diffs @15, curva por duración (Swift
   Charts), power spikes comparados (nivel 6 y 1.º–3.º legendario de `champion_profiles`:
   "Zed llega a 6 a los 7:10, vos a los 7:40") y **claves**. Las claves son los tips curados
   del archivo de tips del locale (§14.12) para (campeón, rol, rival); si el tip se revisó en
   un parche anterior se muestra "revisado en 16.20". Sin tip curado, plantillas generadas por
   datos.
2. **Composición:** perfil de daño de ambos equipos (ponderado por `dmg_per_min`), perfiles
   del rival (`heavy_ad`, `heavy_cc`…), frontline, CC, early vs late (de `duration_curves`),
   power spikes de cada equipo y "condiciones de victoria" textuales derivadas (por ejemplo,
   "Ustedes: early fuerte, buscar cerrar antes del minuto 30").
3. **Build:** runas, ítems por capas con alternativas, spells y habilidades, cada uno con su
   winrate, muestra y motivo.
4. **Mi historial:** tu rendimiento con ese campeón, vs ese rival y en ese rol.

En inicio de parche, el encabezado muestra "Datos 16.21 + 16.20" desde `meta.blend_patches`
(§14.13).

### 20.3 Estados especiales

- **Blind pick / sin roles:** el rol se infiere de tus preferencias o se elige manualmente.
  Por defecto (`DraftRecommendations.blindRole`): el rol donde tenés más partidas propias con
  el campeón que lockeaste o tenés en hover; si no hay, el rol con más campeones en tu pool
  declarado; si tampoco, MIDDLE. Los empates van al rol que se declara antes (top, jungle,
  middle, bottom, utility). El selector de la columna (§20.1) lo cambia y la elección dura lo que
  dura el champ select: no se guarda en settings. ARAM queda sin rol.
- **Flex (440) y Normal Draft (400):** usan el snapshot de la cola 420, sin aviso especial.
- **ARAM (modo degradado en la v1):** solo datos personales y las páginas fijas del usuario.
  Sin estadísticas de ARAM; llegan después, en un archivo aparte.
- **Rival de lane desconocido:** se muestran recomendaciones "seguras" (mejor promedio
  contra los rivales más probables del rol, ponderado por pick rate).
- **Sin snapshot descargado:** modo degradado. Funcionan el auto-accept, las páginas fijas
  por campeón y la capa personal. Implementado hoy (P6-06): `SnapshotModel.provider` no tiene
  `meta`, la pestaña Campeones muestra su estado vacío y el importador no importa nada y lo
  avisa una vez por champ select (§13.1). Las páginas fijas por campeón llegan con P8-08.

---

## 21. Configuración y toggles

Todo vive en `MitoSettings` (Codable) más las tablas de overrides en la base personal.
`SettingsStore` (actor en `MitoStore`) lo guarda como JSON legible (pretty-printed, claves
ordenadas) en `~/Library/Application Support/<bundle id>/settings.json`, así Debug y Release
no comparten datos (§24). Cada guardado es atómico y no se intercalan: gana el último. Al
cargar, un archivo ausente da los defaults y una clave faltante o desconocida se tolera; un
archivo corrupto o ilegible también da los defaults, pero antes se mueve a
`settings.corrupt-<timestamp>.json` en la misma carpeta, nunca se borra. El contenido nunca se
loguea. `AppModel` lo carga al arrancar y guarda cada cambio con debounce (§9.3).

### 21.1 General

| Setting | Tipo | Default |
|---|---|---|
| Abrir Mito al iniciar sesión | bool | off |
| Mostrar ventana al entrar en champ select | bool | on |
| Ícono en la barra de menú | bool | on |
| Ícono en el Dock | bool | off |
| Idioma | es-AR / en | sistema |
| Ruta de instalación de LoL | path | auto |
| Datos Diamante+ (capa sobre la base Esmeralda+) | auto (según tu elo) / on / off | auto |

La pestaña "General" (`Features/Onboarding/OnboardingSettingsTab`, modelo `OnboardingModel`)
es un `Form` agrupado en cuatro secciones:

- **General**: toggles, idioma y ruta con bindings a `app.settings.general`. La ruta se elige
  con un selector de archivos y "Detectar sola" la vuelve a `nil`. Por ahora solo "Mostrar
  ventana al entrar en champ select" tiene efecto (§20.1); el resto se guarda y el pie de la
  sección lo dice.
- **Pool de campeones** (§19.1.3): un selector de rol y la lista ordenada del rol, que se lee
  y se guarda con `PersonalStore.pool(for:)` / `setPool(_:for:)`. El primero es el principal.
  Cada fila tiene subir, bajar y quitar (con etiquetas de VoiceOver); cada cambio guarda el
  pool entero del rol y, si falla, se deshace y se avisa. Si el pool no se puede leer, la
  edición se apaga. "Agregar campeón…" abre un buscador sobre los campeones del `GameData`
  compartido (`GameData.allChampions`, §9.3, sin el `-1` "None"), sin los que ya están en el
  pool; sin datos del cliente se deshabilita y el pie explica por qué.
- **Flash**: el mismo `app.settings.importing.flashPosition` de §21.4, más una sugerencia
  leída del historial guardado: de las últimas 20 partidas (`PersonalStore.matches`), cuántas
  tenían Flash (4) en D (`spells.first`) y cuántas en F. Las partidas sin Flash no cuentan.
  Se muestra "Detectado: F en 18 de 20 partidas"; con empate o sin partidas con Flash no hay
  mayoría. `OnboardingModel.resolvedFlashSlot(_:)` resuelve `auto` a la mayoría (o a nada), y
  el importador la usa para el slot de Flash (§13.3).
- **Datos**: el picker de "Datos Diamante+" (`diamondPlusData`). La capa todavía no se
  descarga.

No hay flujo de primer arranque: todo se configura desde Settings.

### 21.2 Partida

| Setting | Tipo | Default |
|---|---|---|
| Auto-accept | off / siempre / solo colas elegidas | siempre |
| Colas del auto-accept (solo con "solo colas elegidas") | Clasificatoria solo/dúo (420), Clasificatoria flexible (440), Normal de reclutamiento (400), Normal a ciegas (430), ARAM (450) | ninguna |
| Delay del auto-accept | 0–8 s, de a 1 s | 2 s |
| Notificar partida encontrada | bool | on |

La pestaña "Partida" (`Features/Gameflow/GameflowSettingsTab`) es un `Form` agrupado con
bindings a `app.settings.game`: un picker para el modo, un stepper para el delay (deshabilitado
con `off`), un toggle por cola que aparece solo con "solo colas elegidas" y el toggle de la
notificación. `GameflowModel` lee los settings en cada decisión del auto-accept, así que un
cambio vale desde el próximo ready check (o desde la relectura, si hay uno esperando el delay).
La cola sale de `GET /lol-gameflow/v1/session` cada vez que el auto-accept decide; si no se
puede leer, queda desconocida y "solo colas elegidas" no acepta (§11.3).

### 21.3 Champ select

| Setting | Tipo | Default |
|---|---|---|
| Recomendaciones de pick | bool | on |
| Recomendaciones de ban | bool | on |
| Candidatos | mi pool / que tengo / todos | que tengo |
| Slider Meta ↔ Comfort | 0–1 | 0,5 |
| Auto-hover del recomendado | bool | off |
| Auto-ban | off / lista / recomendado | off |
| Auto-pick | off / lista por rol | off |

### 21.4 Importación

| Setting | Tipo | Default |
|---|---|---|
| Importar runas | bool | on |
| Modo de runas | adaptativo (matchup) / general / fijo por campeón | adaptativo |
| Página a usar | página Mito / página N / la actual | página Mito |
| Importar spells | bool | on |
| Posición de Flash | D / F / auto | auto |
| Importar item sets | bool | on |
| Limpiar sets viejos de Mito | bool | on |
| Importar al hacer hover | bool | off |
| Re-importar si cambia el rival | bool | on |
| No pisar cambios manuales | bool | on |

La pestaña "Importación" (`Features/Import/ImportSettingsTab`) es un `Form` agrupado con
bindings a `app.settings.importing`, en secciones Runas, Spells, Ítems y Cuándo importar. Cada
opción dependiente se deshabilita con su toggle apagado (modo y página con "Importar runas",
Flash con "Importar spells", limpiar sets con "Importar item sets"). Con "Una página elegida"
aparece un picker con las páginas editables del cliente (`GET /lol-perks/v1/pages`) que guarda
`reservedRunePageID`; un ID guardado que ya no está en el cliente se muestra como tal.

- **Modo de runas** (§13.1): "Fijo por campeón" usa la página fija del override del campeón y,
  si no hay, la general con un aviso en el toast; "General" importa la página general y
  "Adaptativo" la adaptada al rival de línea o al perfil del equipo rival (§18.6). Un override
  con runas en "General" o "Página fija" gana sobre este; uno en "Adaptativo" lo sigue.
- **Posición de Flash**: "Automática" usa el slot detectado de las últimas 20 partidas
  (§21.1); sin mayoría, el slot donde el jugador ya tiene Flash en la sesión (§13.3).
- Los toggles de importar runas, spells e item sets ganan siempre sobre los overrides.
- **Re-importar si cambia el rival** (§13.1): durante el champ select, si se revela el rival de
  lane o cambia el perfil del equipo rival, se re-envía solo la parte que cambia (runas, spells
  o ítems), nunca una fija del override ni una confirmación de runas sin responder.
- **No pisar cambios manuales** (§13.1): antes de re-enviar una parte se compara lo que tiene el
  cliente con lo que puso Mito; si el usuario la cambió (o puso otra página como actual), queda
  como está y el toast lo dice. Apagado, el re-import pisa sin mirar.

Los toggles rápidos de la barra de menú (§22.4, `QuickTogglesMenuSection`) escriben los mismos
settings: "Importar runas", "Importar ítems" y "Auto-accept" (§21.2). Este último está tildado
con cualquier modo distinto de `off`; destildarlo pone `off` y volver a tildarlo pone `siempre`.
Las colas elegidas quedan guardadas para la pestaña "Partida".

### 21.5 Overrides por campeón

Pantalla con buscador de campeones. Por cada (campeón, rol):

- Runas: adaptativo / general / página fija (editor visual de runas nativo).
- Spells: recomendado / fijo.
- Ítems: recomendado / set fijo / no importar.
- Marcar como favorito o excluir del pool.

Implementación (`Features/Overrides`). Cada (campeón, rol) es un `ChampionOverride` de la base
personal (§17), leído con `overrides()`, guardado con `save(_:)` y borrado con
`deleteOverride(champion:role:)`. Los nombres, árboles de runas, spells e ítems salen del
`GameData` compartido (§9.3); sin datos del cliente la pantalla muestra un estado vacío
"Sin datos del cliente" y no se edita nada.

- Lista con buscador por nombre (en el locale del cliente): arriba los overrides guardados,
  ordenados por campeón y rol, con el resumen de modos y las marcas de favorito y excluido
  (ícono, tooltip y etiqueta de VoiceOver); debajo todos los campeones. Doble clic, Return o
  "Editar…" abre el editor.
- El editor es una hoja con Cancelar, Guardar y, si hay override guardado, Eliminar (con
  confirmación). Se guarda solo con Guardar. Con cambios sin guardar no se cambia de rol.
- Runas: un picker por fila, ubicadas por tipo de fila (`keystone`, `regular`, `statMod`) y
  nunca por posición. Rama principal, runa clave, 3 filas principales, rama secundaria (nunca
  la misma), 2 runas secundarias de filas distintas (una tercera reemplaza a la más vieja,
  como en el cliente) y 3 fragmentos de las filas de la principal. Al cambiar la principal se
  conservan los fragmentos que siguen en su fila. La página fija solo se guarda completa y
  válida según `RunePage.validationError(against:)` de `MitoImport`, el mismo validador del
  importador (§13.2).
- Spells: dos pickers con los spells de `CLASSIC` (`SummonerSpell.gameModes`); el fijo pide
  dos distintos, en el orden de la `SpellPair` (la posición de Flash la sigue resolviendo el
  importador, §13.3).
- Ítems: el set fijo es una lista de bloques con título y una búsqueda de ítems por nombre;
  repetir un ítem en un bloque sube su cantidad. Necesita al menos un ítem. La búsqueda
  todavía muestra ítems de otros modos y retirados: `Item` no trae mapa ni si está en tienda.
- Los valores fijos se conservan aunque el modo no sea fijo, así cambiar de modo no los
  pierde; solo el modo fijo los exige.

**En el import (P8-09, §13.1).** El importador lee el override de (campeón, rol) del rol que
resolvió. Precedencia: los toggles globales de §21.4 ganan siempre (una parte apagada se
saltea diga lo que diga el override); después el modo del override, sobre la build adaptada
al rival y al perfil rival (P7-10). En runas, "Página fija" manda su página y "General" la
general (nunca la adaptada), diga lo que diga el global; "Adaptativo" (el default del editor,
sin preferencia), un modo desconocido o la falta de override siguen el modo global de §21.4:
"Fijo por campeón" usa la página fija guardada, "General" la general y "Adaptativo" la
adaptada. "Recomendado" en spells e ítems es el par y la build adaptados. Fallbacks: una página fija que ya no valida no se envía y el toast
dice por qué, nunca se cae a la general en silencio; un modo fijo sin valor guardado, o
"Fijo por campeón" sin página, usa la general y lo dice ("· sin fija guardada, va la
general"). "No importar" ítems no envía set y deja el set de Mito que hubiera. Las partes que
salieron del override llevan "· override" en el toast, y cada parte queda en `import_log`.
Favorito y excluido del pool no cambian el import.

---

## 22. Diseño de UI nativa

### 22.1 Principios

- **Se tiene que sentir como una app de Apple**: barra lateral, toolbar, Settings estándar,
  atajos de teclado, modo oscuro y claro, accesibilidad (VoiceOver, Dynamic Type donde
  aplique, contraste).
- **Nada de webviews.** Todo SwiftUI.
- **Densidad informativa alta pero limpia**: las recomendaciones se leen en 2 segundos.
- **Colores semánticos**: verde = favorable, rojo = desfavorable, gris = muestra baja. No
  depender solo del color: incluir íconos y signos (+/−).
- **Animaciones sutiles** al actualizarse el draft (`.contentTransition(.numericText())`,
  `matchedGeometryEffect` en los slots).
- **Liquid Glass** en toolbar y sidebar donde el sistema lo soporte, con fallback
  `.regularMaterial` en versiones previas.

### 22.2 Navegación (ventana principal)

`NavigationSplitView` con sidebar:

- **Ahora** (estado actual: lobby, champ select o en partida)
- **Campeones** (tier list del parche por rol, ficha de campeón)
- **Mi perfil** (historial, mejores campeones, insights)
- **Overrides** (configuración por campeón)

**Campeones.** `ChampionsModel` lee el `StatsProvider` del snapshot abierto y el `GameData`
compartido (§9.3) con closures; todos los números salen de `MitoEngine/Stats` (§18.1, §18.2),
nunca se recalculan en la app.

- Selector de rol segmentado en la toolbar: TOP, JGL, MID, ADC, SUP.
- Encabezado con el parche y las partidas de `meta` ("Parche 16.21 · 412.339 partidas"), con
  el formato de números del locale.
- Tabla con tier, campeón, WR (`wr_smoothed(champ, role)`), PR (`games / meta.matches`) y
  partidas. Orden: por tier (S a D) y, dentro del tier, por WR suavizado. El tier siempre se
  muestra como letra; el color solo la acompaña.
- Debajo del "confiable" de `champ_role` la fila lleva el ícono de "muestra baja" (gris, con
  tooltip y etiqueta de VoiceOver). Una fila debajo del mínimo no entra en la tier list
  (§18.2: esos datos no se usan); en la ficha del campeón sí aparece, con "—" en el tier y la
  marca de muestra baja.
- Nombres en el locale del cliente; mientras no cargan, "Campeón 103".
- Sin snapshot (`meta == nil`): estado vacío "Sin estadísticas todavía", con el modo degradado
  de §20.3.
- Doble clic (o Return) en una fila abre la ficha del campeón: sus stats en cada rol donde
  tiene fila este parche (mismas columnas) y un lugar reservado para la build recomendada, que
  llega con el motor de loadouts.

**Mi perfil.** `ProfileModel` lee de la base personal el historial, el pool y los overrides al
arrancar, al terminar cada sincronización y cada vez que se abre el destino (el pool y los
overrides se editan en otros lados). Las estadísticas salen del snapshot abierto con un
closure, como en Campeones; la maestría se lee en vivo con `championMastery` en cada entrada
a `connected` y se descarta al salir (§17); si el pedido falla, no hay maestría
(`mastery_norm` 0).

- Arriba, la línea de estado de la sincronización (§19.1).
- **Insights** (§19.4): tilt, partidas cortas, y los 3 mejores y 3 peores matchups con
  victorias, partidas y porcentaje. Sin ninguno: "Todavía no hay suficientes partidas para
  sacar conclusiones".
- **Mejores campeones por rol**: un bloque por rol con partidas propias (cualquier cola; las
  partidas sin rol no entran), hasta 5 campeones ordenados por `personal(c, r)` de
  `PersonalScoring` (§19.3). Columnas: el score en puntos de winrate (`winratePoints()`),
  partidas, WR propio, ventaja contra el promedio (`my_wr_smoothed − wr_s`), comfort, pool,
  rendimiento relativo, y KDA y CS/min contra el promedio. Cada valor con signo lleva flecha y
  signo, y el color solo los acompaña.
- Sin historial: estado vacío "Sin historial", que explica que aparece cuando Mito se conecta
  al cliente, con la línea de estado debajo.

### 22.3 Componentes del design system

- `ChampionIcon(id:size:state:)`: con estados hover, lockeado, baneado y no disponible.
- `WinrateBar(value:baseline:confidence:)`
- `DeltaBadge(delta:)`: "+2,1" / "−3,4" con color e ícono.
- `ConfidenceIndicator(level:)`
- `RunePageView(page:)`: visual con los árboles y las runas elegidas.
- `ItemRow(items:title:)`
- `ReasonRow(reason:)`: texto con ícono SF Symbol.
- `TeamColumn(slots:side:)`
- `DurationCurveChart(curve:)`: Swift Charts.
- `DamageProfileBar(phys:magic:true:)`

Implementados en `Mito/DesignSystem/` (textos en `DesignSystem.xcstrings`):

- `DeltaBadge(delta:)`: el delta (fracción) en puntos de winrate con un decimal y el formato del
  locale; `+` o `−` (U+2212) y flecha arriba o abajo, en verde o rojo. Lo que redondea a 0,0 va
  sin signo, con `equal` y en gris. VoiceOver lee "+2,1 puntos de winrate".
- `ConfidenceIndicator(level:)`: "conf. alta" con sello verde (`reliable`), "muestra baja" con
  ícono gris (`usable`) y "sin muestra" (`belowMinimum`).
- `ReasonRow(reason:names:)`: un ícono SF Symbol por caso de `Reason.Kind`, en el tono de la
  razón, y su línea en es-AR (`ReasonText.text`, que es lo que se testea). Los deltas van en
  puntos ("+2,1 vs Zed (8.212 partidas)", "−4,2 para tu Ahri"), los shares en porcentaje ("Tu
  equipo es 78 % AD: aporta AP") y las partidas con separador de miles. El tono sigue al signo del
  delta; el tier es favorable en S y A, neutro en B y desfavorable en C y D; las de comp fit son
  favorables y las de loadout neutras. Una razón con muestra debajo de "confiable" lleva la marca
  "muestra baja". Los nombres de campeones e ítems los pasa la feature (`ReasonNames`), con
  "Campeón 103" mientras no cargan.
  - El matchup estimado por perfil (`profileMatchup`) dice que es un estimado y con qué perfiles:
    "+1,2 vs Zed (estimado por perfil: mucho AD, 797 partidas)", con otro ícono que el matchup
    directo. Varios perfiles se unen como lista del locale ("mucho AD y mucho CC") con las
    mismas etiquetas que el import ("mucho AD", "mucho AP", "daño mixto", "mucho CC"); una
    etiqueta desconocida va tal cual. El tono sigue al signo, como el matchup.
  - La comodidad (`comfort`) nombra el puesto en el pool del rol con ordinales abreviados
    delante de "campeón": el 1 es "Tu campeón principal"; los que terminan en "primer" o
    "tercer" se apocopan ("Tu 3.er campeón", también 13, 21, 23…) y el resto lleva "º" ("Tu 2.º
    campeón", "Tu 11.º campeón"), seguido de "(41 partidas, 56 %)". Fuera del pool: "41
    partidas tuyas, 56 %". El winrate va en porcentaje del locale y es favorable si redondea a
    más de 50 %; si no, neutro: la comodidad nunca es mala noticia.
- `WinrateBar(value:baseline:confidence:)`: la distancia `value − baseline` como barra que
  crece desde una línea central, a la derecha si es favorable y a la izquierda si no, así el
  lado lleva el signo y el color solo lo acompaña. Media barra son 5 puntos de winrate; más
  allá se llena. Redondea como `DeltaBadge`, así que lo que da 0,0 no tiene barra. Debajo de
  "confiable" va en gris. VoiceOver lee "+3,8 puntos de winrate, conf. alta"
  (`WinrateBar.accessibilityText`, que es lo que se testea).

### 22.4 Barra de menú

```
● Mito — Conectado
──────────────────────────────
Fase: Champ select (tu turno)
Recomendado: Ahri (+3,8)
──────────────────────────────
✓ Auto-accept
✓ Importar runas
✓ Importar ítems
──────────────────────────────
Abrir Mito                ⌘O
Settings…                 ⌘,
Salir                     ⌘Q
```

La línea "Recomendado: Ahri (+3,8)" (`RecommendationMenuSection`) va debajo del resumen del
draft: el pick #1 de la columna "Recomendados" (§20.1) con su score en puntos de winrate, con el
mismo formato que `DeltaBadge`. Durante la fase de bans dice "Ban recomendado: Malzahar", sin
número. Sin snapshot, sin rol, con el setting apagado o sin candidatos no aparece. Es solo una
sugerencia: no tiene acción (§5).

La primera línea es el estado de `connection.states()` (§11.2), una sola línea sin acciones:

| Estado | Texto | Símbolo |
|---|---|---|
| `searching` | Mito — Buscando el cliente… | `circle.dashed`, gris |
| `connecting` | Mito — Conectando… | `circle.dashed`, gris, con pulso |
| `connected` | Mito — Conectado como Joaco#LAS (o Mito — Conectado sin Riot ID) | `circle.fill`, verde |

El color siempre va con el cambio de símbolo y de texto; VoiceOver lee solo el texto. El
Riot ID sale de `LCUEndpoint.currentSummoner` (§10.6), no de `states()`: `ConnectionModel` lo
pide al entrar en `connected` y de nuevo con cada evento de `currentSummoner` (cambio de
cuenta), y lo borra al salir de `connected`. Si la llamada falla o `riotID` es `nil`, la línea
queda en "Mito — Conectado", sin marcar error. Una respuesta que llega después de que la
conexión cayó, o de que salió un pedido más nuevo, se descarta. El Riot ID es la identidad del
propio usuario, no de otros jugadores, y no se loguea.

Ícono de la barra según el estado (SF Symbols): desconectado `circle.dashed`, conectado
`circle.fill`, buscando partida `magnifyingglass`, champ select `person.3.fill`, en partida
`gamecontroller.fill`.

### 22.5 Notificaciones (UserNotifications)

- "Partida encontrada, aceptada": cuando el auto-accept reporta `.accepted` y
  `notifyMatchFound` está on.
- "Partida encontrada": cuando el auto-accept reporta `.skipped` por `.disabled`,
  `.queueNotSelected` o `.unknownQueue` y `notifyMatchFound` está on; es el "solo notificar"
  de `off` (§11.3). Las otras razones (`.alreadyAnswered`, `.notInProgress`,
  `.readyCheckEnded`) y un accept fallido no notifican. Las dos usan
  `MitoNotification.matchFound`, y el auto-accept decide una sola vez por ready check, así
  que sale como mucho una por ready check.
- "Te toca elegir. Recomendado: Ahri"
- "Importado para Ahri MID", "Confirmá las runas para Ahri MID" o "No se pudo importar todo
  para Ahri MID": el resultado del import (§13.1), como `MitoNotification.loadoutImported`,
  cuando la ventana principal no está al frente.
- Acción en la notificación: "Abrir análisis".

Las publica `SystemNotificationPoster` (`App/MitoNotification.swift`) detrás del protocolo
`NotificationPosting`: `post(_:title:)` recibe el caso de `MitoNotification` y el título ya
localizado en la tabla de la feature dueña. Pide permiso (alerta y sonido) en el primer post y
nunca más; sin permiso el post se descarta sin error, y un permiso dado después en Ajustes del
Sistema vale desde el próximo. El identificador es uno por caso, así que una notificación nueva
reemplaza a la anterior del mismo tipo. Con Mito en primer plano el sistema no la muestra.

### 22.6 Localización

- `String Catalogs` (`.xcstrings`) desde el día 1.
- Nombres de campeones, ítems y runas: desde los datos estáticos en el locale del cliente o
  `es_AR`. El snapshot no trae nombres.
- Números con el formateador del locale (coma decimal en es-AR).

---

## 23. Testing y entorno de desarrollo

### 23.1 Mock LCU (`tools/lcu-mock`)

Servidor Python (aiohttp) que simula la LCU para desarrollar sin abrir el juego ni hacer
cola:

- Escribe un lockfile falso en una ruta configurable.
- HTTPS con certificado self-signed propio en `127.0.0.1`.
- Endpoints REST con respuestas desde fixtures JSON.
- WebSocket WAMP que **reproduce secuencias grabadas** (ready check → champ select
  completo → partida) con timing real o acelerado.
- Endpoints de escritura (`POST /lol-perks/v1/pages`, etc.) que validan el payload y lo
  guardan para que el test lo inspeccione.

```bash
uv run lcu-mock --scenario ../../fixtures/lcu/ready-check --speed 4x
```

`--scenario` es un directorio en formato v0 (`fixtures/lcu/README.md`), grabado o sintético.
La reproducción arranca con la primera suscripción WAMP. La app de Debug lo encuentra con
`-MitoLCULockfilePath <ruta absoluta del lockfile>` (§9.3, §10.2) y lee solo ese lockfile; no
hace falta aceptar otra CA porque la app ya acepta el certificado solo para `127.0.0.1`
(§10.3). El certificado del mock se genera en cada arranque
y nunca se guarda.

### 23.2 Recorder (`tools/lcu-recorder`)

- Se conecta a la LCU real y graba todos los eventos WAMP y las respuestas de los GET
  relevantes, con timestamps, a `fixtures/lcu/<escenario>/` (formato en
  `fixtures/lcu/README.md`).
- Anonimiza puuids, nombres e IDs antes de guardar.
- Se usa para crear escenarios del mock y para detectar cambios de la LCU entre parches.

### 23.3 Tests

- **MitoEngine:** unit tests con un `StatsProvider` en memoria. Casos: matchup conocido,
  backoff por muestra baja, comp sin frontline, rival de lane inferido con baja confianza,
  campeón sin `champion_roles`, ARAM en modo degradado (sin estadísticas, solo capa personal
  y páginas fijas).
- **LCUKit:** parsing de lockfile y de args de proceso, decodificación tolerante de
  sesiones reales grabadas, reconexión.
- **Importer:** contra el mock, verificando el payload exacto de runas e item sets, que no
  pise los sets del usuario y el manejo del cupo de páginas.
- **mito-data:** pytest para normalización, filtros de remake, clasificación de ítems,
  agregaciones sobre un dataset chico fijo y validación del schema exportado.
- **Contrato snapshot ↔ app:** `SnapshotContractTests` (MitoStoreTests) abre el snapshot de
  ejemplo de `fixtures/snapshot/` (generado por `mito-data`) con `SnapshotReader` y verifica
  `schema_version`, la identidad de `meta`, las claves JSON de `meta` y cada consulta de
  `StatsProvider` contra valores leídos del archivo, incluido el fallback de ítems finales
  (Zed JUNGLE, `tl_games` 40), la fila única que queda bajo el mínimo y el `max_order` de 4
  letras (Udyr JUNGLE). `SnapshotRelationContractTests` hace lo mismo con las tablas de
  Fase 7: matchups y sinergias servidos desde la fila de cada lado (A vs B y B vs A),
  `vs_team_stats` coherente en las dos orientaciones (A vs B sumado sobre los roles de A es
  B vs A sumado sobre los de B, con wins complementarios: Ahri vs Zed), `champion_profiles`
  con todas sus columnas (Zed JUNGLE sin `item3_s`),
  `champ_vs_profile`, páginas e ítems finales por perfil con `'any'` como línea base y no
  como perfil, loadouts por rival sin cruzarse con los generales (ni en un sentido ni en el
  otro), bans, flags, `meta.profile_rules` y las curvas de duración, cuyos buckets suman las
  partidas y las victorias de `champ_role_stats` (Ahri MIDDLE). `SnapshotReaderTests` cubre
  los errores (archivo ausente o corrupto, `schema_version` no soportado, clave de `meta` faltante o mal
  formada, `profile_rules` mal formado, tabla de Fase 7 faltante) y la tolerancia (sin
  `profile_rules` abre con `profileRules == nil`; flags y perfiles desconocidos quedan como
  `.unknown`) sobre copias temporales. `ContractPinTests` (ArchitectureTests) fija las tablas
  y columnas de `schema.sql` que lee el reader, y que toda tabla del schema esté leída o
  listada como no leída: un cambio de schema sin cambio de reader falla.
- **Cómo se corren:** `swift test --package-path apps/macos/MitoKit --enable-code-coverage`.
  Los tests de la app (`MitoTests`) corren con
  `xcodebuild -project apps/macos/Mito.xcodeproj -scheme Mito -destination 'platform=macOS' test`.
  La CI (GitHub Actions, runner `xcode-27`) corre los dos: los de MitoKit con warnings como
  errores y el build + tests de la app, en cada push a `main`/`dev` y en PRs hacia ellas. Antes de la beta se suma un test plan con
  configuraciones de Thread y Address Sanitizer.
- **Agente de tests:** `.claude/agents/test-engineer.md` audita cada función contra su
  propósito, agrega solo los tests que faltan y mide coverage.

### 23.4 Calidad de las recomendaciones (offline)

Backtest sobre partidas del parche que no se usaron para agregar (holdout del 10 %):

- ¿El score de composición predice la victoria mejor que el azar? Métricas: AUC y log-loss.
- Calibración: los equipos con +3 puntos estimados ¿ganan cerca del 53 %?
- Sirve para ajustar los pesos `w_*` con datos y no a ojo.

---

## 24. Distribución

- **Fuera del Mac App Store**: la app necesita leer fuera de su contenedor (lockfile,
  `ps`), así que el App Sandbox está **desactivado**.
- Firma con **Developer ID** + **notarización** de Apple + Hardened Runtime (solo en
  Release; Debug va sin hardened runtime porque se firma ad-hoc).
- **Sin entitlements**: sin sandbox, ni localhost ni leer los argumentos de un proceso del
  mismo usuario necesitan excepciones del hardened runtime.
- `LSUIElement = YES`: arranca solo en la barra de menú y pasa a `.regular` mientras la
  ventana principal o Settings están abiertas, según el toggle de Dock (§21.1).
- Debug y Release conviven: bundle IDs distintos, así que todo lo que se guarda por instalación
  se nombra a partir del bundle ID.
- La beta es un Release publicado en el canal `beta` de Sparkle, no otra configuración.
- Actualizaciones con **Sparkle** (appcast firmado con EdDSA).
- Instalación por DMG. Opcional: cask de Homebrew.
- Permisos de macOS: notificaciones. No hace falta Accesibilidad ni Grabación de pantalla
  en la v1.

---

## 25. Seguridad y privacidad

- El token de la LCU se mantiene solo en memoria y **nunca** se loguea.
- Los logs con `os.Logger` usan `privacy: .private` para puuids y nombres.
- La API key de Riot vive solo en el pipeline (variables de entorno o secret manager). Nunca
  en el repo ni en la app.
- La app no tiene telemetría en la v1. Si se agrega, será opt-in, anónima y documentada.
- Los datos personales quedan en el Mac (Application Support). Hay un botón "Borrar mis
  datos".
- El snapshot y los tips se verifican por `sha256` (del archivo comprimido) contra el
  manifest antes de descomprimirse, y el SQLite descomprimido contra `raw_bytes`. El manifest
  se sirve por HTTPS (opcional: firmarlo).
- Las conexiones a la LCU aceptan el certificado **solo** para `127.0.0.1`.

---

## 26. Roadmap por fases

Cada fase termina con algo usable. Las unidades de cada fase, sus dependencias y su estado
están en `docs/roadmap.md`, que es el backlog; acá queda el objetivo de cada fase. Desde la
Fase 1 las unidades corren en paralelo según ADR 0006.

### Fase 0 — Setup (½ semana)

Repo, documentación, módulos de MitoKit con los contratos compartidos, shell de la app con un
slot por feature, targets de tests y CI; `mito-data` inicial y la personal API key de Riot.

**Hecho cuando:** `swift test` y `xcodebuild test` pasan en local y en la CI, y cada unidad de
la Fase 1 tiene su carpeta y su lane sin tocar archivos compartidos.

### Fase 1 — Conexión (1 semana)

Descubrimiento del cliente, `LCUClient` REST con TLS restringido a 127.0.0.1, WebSocket WAMP
con reconexión, estado de conexión en la barra de menú y `tools/lcu-recorder`.

**Hecho cuando:** abrir el cliente y ver "Conectado como X" en menos de 3 s, y que se
reconecte solo al reiniciar el cliente.

### Fase 2 — Gameflow + auto-accept (½ semana)

Máquina de estados de gameflow, auto-accept con delay y notificación, y `tools/lcu-mock` con
el escenario de ready check.

**Hecho cuando:** hacer cola, irse a otra app y que la partida se acepte sola con
notificación.

### Fase 3 — Champ select en vivo (1 semana)

Decodificación tolerante de la sesión, `DraftContext`, inferencia de roles rivales y la vista
de champ select (equipos, bans, timer) sin recomendaciones todavía.

### Fase 4 — Importador con datos fijos (1 semana)

Datos estáticos desde el cliente local, importador de runas, spells e item sets con builds
escritos a mano para 5 campeones, gestión de páginas y sets sin pisar los del usuario, y
settings de importación.

**Hecho cuando:** lockear Ahri y que aparezcan runas, spells y el item set correctos.

### Fase 5 — Pipeline MVP (2 semanas, en paralelo con 3–4)

En `mito-data`: cliente de la Riot API con rate limiter, crawl de un parche de LAS alto elo,
normalización, agregaciones base y export `.sqlite.xz` publicado en R2. En este repo: el
fixture en `fixtures/snapshot/`.

### Fase 6 — La app consume el snapshot (1 semana)

Descarga y verificación del snapshot, `MitoStore` read-only, el importador con datos reales
(general, sin matchup) y la ficha de campeón con la tier list por rol.

### Fase 7 — Motor de recomendaciones v1 (2 semanas)

Agregaciones de matchup, sinergia y perfiles en `mito-data`; score de pick y de ban; runas,
ítems y spells adaptados al matchup y al perfil rival; razones explicables.

### Fase 8 — Capa personal (1 semana)

Historial vía LCU a la base personal, onboarding, score personal con el slider Meta ↔ Comfort,
"Mi perfil" con insights y overrides por campeón (§21.5).

### Fase 9 — Análisis pre-partida completo (1–2 semanas)

Pestañas Matchup, Composición, Build y Mi historial con Swift Charts, tips curados es-AR,
estados especiales (§20.3) y pulido visual y de accesibilidad.

### Fase 10 — Release beta (1 semana)

Firma, notarización, Sparkle y DMG; disclaimer legal y "Acerca de"; registro en el Riot
Developer Portal si se distribuye; beta con amigos.

### Después (v1.5 / v2)

- Backtest y ajuste de pesos con regresión logística.
- Cold start de parche refinado.
- Historial personal profundo vía pipeline.
- Flex con datos propios; archivo aparte de estadísticas de ARAM.
- Capa `master_plus`, cuando el volumen lo justifique.
- **Overlay y Live Client Data (v2).**
- Post-game.

---

## 27. Overlay (v2) — notas para después

Queda fuera de la v1 a propósito. Notas para cuando se retome:

- **Fuente de datos:** Live Client Data API, `https://127.0.0.1:2999/liveclientdata/allgamedata`
  (también `activeplayer`, `playerlist`, `eventdata`). Solo existe mientras corre la
  partida. Certificado self-signed de Riot.
- **Ventana:** `NSPanel` sin bordes, `isOpaque = false`, `backgroundColor = .clear`,
  `ignoresMouseEvents = true`, `level = .statusBar` (probar niveles más altos si hace
  falta), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`,
  `hidesOnDeactivate = false`. Contenido en SwiftUI vía `NSHostingView`.
- **Modo de ventana del juego:** funciona seguro en ventana sin bordes. El fullscreen de
  macOS usa un Space propio: hay que probar `.fullScreenAuxiliary` contra la versión actual
  del cliente. Probablemente sea lo que hoy le falla a Blitz en Mac.
- **Contenido permitido:** solo información que el juego ya da o que estaba disponible antes
  de la partida (build planificada, recordatorios de runas, power spikes del plan). **Nada**
  de timers de enemigos ni información oculta.
- **Interacción:** atajo global para mostrar u ocultar (por ejemplo, ⌥Tab), con un modo
  "editar posición" que activa los clics temporalmente.
- **Riesgo:** el área con más chances de romper la política de Riot o de cambiar con mVG.
  Revisar la política vigente antes de implementar.

---

## 28. Riesgos y preguntas abiertas

### Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Riot restringe la LCU o algún endpoint | Alto | Decodificación tolerante, recorder para detectar cambios rápido, features degradables |
| Cambios de política de terceros | Alto | Solo APIs oficiales, nada in-game en la v1, seguir el portal de desarrolladores |
| Rate limits que no alcanzan para matchups | Medio | Production key, foco en un bracket amplio, timelines con muestreo estratificado, mezcla de parches |
| Pocos datos al inicio de parche | Medio | Cold start con el parche anterior, aviso visible |
| Calidad de la recomendación "a ojo" | Medio | Backtest, calibración y razones visibles para que el usuario juzgue |
| Cambio de estructura de runas o shards | Bajo | Validar siempre contra `perkstyles.json` del cliente |
| Costo de hosting del snapshot | Bajo | Archivos estáticos comprimidos, R2 sin egress |

### Preguntas abiertas

1. ¿La capa Diamante+ en "auto" se activa solo para usuarios Diamante+ o para todos
   (aprender del mejor)?
2. ¿Se hace pública Mito o es uso personal y amigos? Define si hace falta production key y
   registro formal.
3. ~~¿Hosting del snapshot?~~ Resuelto: Cloudflare R2 (ADR 0005).
4. ~~¿Tips de matchup curados a mano o solo generados por datos?~~ Resuelto: curados a mano
   en la v1, como archivo aparte por locale (es-AR primero) con plantillas por datos de
   fallback (§14.12, ADR 0005).
5. ¿Auto-pick existe en la v1 o se deja directamente afuera?
6. ¿Regiones: solo Américas al principio o desde el día 1 se suma KR/EUW para alto elo?
7. ~~¿Hace falta un backend online antes de la v2?~~ Resuelto: no; snapshot estático por
   parche y bracket (ADR 0005).

---

## 29. Glosario

| Término | Significado |
|---|---|
| **LCU** | League Client Update: el cliente de LoL (UI fuera de la partida) y su API local |
| **LCUx / LeagueClientUx** | Proceso de la UI del cliente; sus argumentos traen puerto y token |
| **WAMP** | Protocolo sobre WebSocket que usa la LCU para eventos (`[5, topic]` para suscribirse) |
| **Gameflow** | Fases del cliente: Lobby, Matchmaking, ReadyCheck, ChampSelect, InProgress… |
| **Champ select** | Selección de campeones (bans, picks, runas, spells) |
| **Hover / intent** | Campeón marcado pero no lockeado |
| **Lock** | Confirmar el pick o ban |
| **Snapshot** | Archivo SQLite (`.sqlite.xz`) con estadísticas agregadas por parche, cola y bracket |
| **Bracket** | Rango de elo de los datos: `emerald_plus` (base) y `diamond_plus` (capa opcional) |
| **Perfil rival** | Clasificación multi-label del equipo rival (`heavy_ad`, `heavy_ap`, `mixed`, `heavy_cc`) |
| **Flag de campeón** | Rasgo curado por parche (`high_heal`, `engage`, `poke`…) en `champion_flags` |
| **Backoff** | Caer a un contexto más general cuando falta muestra |
| **Delta** | Diferencia de winrate contra la línea base del campeón |
| **Comfort** | Familiaridad del usuario con un campeón (partidas, recencia, maestría) |
| **mVG** | Embedded Vanguard, el anti-cheat integrado en LoL para macOS |
| **Data Dragon** | CDN oficial de Riot con datos estáticos por versión |
| **CommunityDragon** | Espejo comunitario de los datos crudos del cliente |
| **match-v5** | Endpoint de la Riot API con el detalle de partidas |
| **Timeline** | Detalle minuto a minuto de una partida (compras, habilidades, eventos) |
| **Roles** | TOP, JUNGLE, MIDDLE, BOTTOM, UTILITY (support) |
| **Colas** | 420 = Ranked Solo/Duo, 440 = Ranked Flex, 400 = Normal Draft, 450 = ARAM |

---

## 30. Referencias

- Riot Developer Portal y políticas: https://developer.riotgames.com/docs/lol
- Data Dragon: https://ddragon.leagueoflegends.com/api/versions.json
- CommunityDragon: https://raw.communitydragon.org/
- Riot Vanguard (wiki, incluye mVG en macOS): https://wiki.leagueoflegends.com/en-us/Riot_Vanguard
- Restricción de acceso a memoria para terceros (Sheep Esports):
  https://www.sheepesports.com/de/articles/riot-explain-league-replays-restrictions-in-new-anti-cheat-update/en
- Cambio de política de anuncios de terceros (Overwolf):
  https://blog.overwolf.com/supporting-creators-in-riots-ecosystem-our-response-and-commitment/
- GRDB.swift: https://github.com/groue/GRDB.swift
- Sparkle: https://sparkle-project.org
- DuckDB: https://duckdb.org
- Polars: https://pola.rs

> **Nota de mantenimiento:** los endpoints de la LCU, los nombres de campos y los límites de
> la Riot API se tienen que verificar contra la realidad (recorder y portal) y actualizar acá
> cuando cambien. Este documento manda; el código lo sigue.
