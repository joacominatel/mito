import MitoAssets
import MitoCore
import MitoEngine
import SwiftUI

/// The "Mi perfil" destination (§22.2); the shell builds it without arguments.
struct ProfileView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ProfileScreen(model: app.profile, gameData: app.clientData.gameData)
    }
}

struct ProfileScreen: View {
    let model: ProfileModel
    let gameData: GameData?

    var body: some View {
        Group {
            if model.history.isEmpty {
                NoHistoryView(status: model.syncStatus)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SyncStatusLine(status: model.syncStatus)
                        InsightsBox(model: model, names: names)
                        ForEach(model.bestChampions, id: \.role) { section in
                            RoleBox(section: section, names: names)
                        }
                    }
                    .padding()
                }
            }
        }
        // The pool and overrides change in other destinations; coming back shows them.
        .task { await model.reload() }
    }

    private var names: ChampionNames { ChampionNames(gameData: gameData) }
}

private struct NoHistoryView: View {
    let status: ProfileModel.SyncStatus

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin historial", tableName: "Profile")
            } icon: {
                Image(systemName: "person.crop.circle")
            }
        } description: {
            VStack(spacing: 8) {
                Text(
                    "Tu historial aparece cuando Mito se conecta al cliente y lee tus últimas partidas.",
                    tableName: "Profile")
                SyncStatusLine(status: status)
            }
        }
    }
}

private struct SyncStatusLine: View {
    let status: ProfileModel.SyncStatus

    var body: some View {
        if let title = status.title {
            HStack(spacing: 6) {
                if status == .syncing {
                    ProgressView().controlSize(.small)
                } else if let symbol = status.symbol {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct InsightsBox: View {
    let model: ProfileModel
    let names: ChampionNames

    var body: some View {
        let matchups = model.matchups
        let shortGames = model.shortGames
        let lossStreak = model.lossStreak
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let lossStreak {
                    Label {
                        Text("Perdiste \(lossStreak) seguidas", tableName: "Profile")
                    } icon: {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                    }
                }
                if let shortGames {
                    ShortGamesLine(insight: shortGames, name: names(shortGames.champion))
                }
                if !matchups.best.isEmpty {
                    MatchupList(
                        title: Text("Tus mejores matchups", tableName: "Profile"),
                        records: matchups.best, isFavorable: true, names: names)
                }
                if !matchups.worst.isEmpty {
                    MatchupList(
                        title: Text("Tus peores matchups", tableName: "Profile"),
                        records: matchups.worst, isFavorable: false, names: names)
                }
                if lossStreak == nil, shortGames == nil, matchups.isEmpty {
                    Text(
                        "Todavía no hay suficientes partidas para sacar conclusiones.",
                        tableName: "Profile"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Insights", tableName: "Profile")
        }
    }
}

private struct ShortGamesLine: View {
    let insight: ShortGameInsight
    let name: String

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(
                    "Ganás \(percent(insight.shortWinrate)) en partidas de menos de 25 minutos con \(name), contra \(percent(insight.longerWinrate)) en las más largas",
                    tableName: "Profile")
                if insight.isLowSample { LowSampleMark() }
            }
        } icon: {
            Image(systemName: "timer")
        }
        .accessibilityElement(children: .combine)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct MatchupList: View {
    let title: Text
    let records: [MatchupRecord]
    let isFavorable: Bool
    let names: ChampionNames

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title.font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(records) { record in
                HStack(spacing: 6) {
                    Image(
                        systemName: isFavorable ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                    )
                    .foregroundStyle(isFavorable ? .green : .red)
                    .accessibilityHidden(true)
                    Text(
                        "\(names(record.id.champion)) vs \(names(record.id.opponent)) (\(String(localized: record.id.role.profileLabel)))",
                        tableName: "Profile")
                    Text(
                        "\(record.wins) de \(record.games) ganadas · \(record.winrate.formatted(.percent.precision(.fractionLength(0))))",
                        tableName: "Profile"
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    if record.isLowSample { LowSampleMark() }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct RoleBox: View {
    let section: RoleChampions
    let names: ChampionNames

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Campeón", tableName: "Profile")
                    Text("Personal", tableName: "Profile")
                        .help(Text("Score personal en puntos de winrate", tableName: "Profile"))
                    Text("Partidas", tableName: "Profile")
                    Text("WR", tableName: "Profile")
                    Text("Vs. promedio", tableName: "Profile")
                        .help(
                            Text(
                                "Tu winrate suavizado menos el del parche", tableName: "Profile"))
                    Text("Comfort", tableName: "Profile")
                    Text("Pool", tableName: "Profile")
                    Text("Rendimiento", tableName: "Profile")
                    Text("KDA", tableName: "Profile")
                    Text("CS/min", tableName: "Profile")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                ForEach(section.rows) { row in
                    ChampionRow(row: row, name: names(row.champion))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(section.role.profileLabel)
        }
    }
}

private struct ChampionRow: View {
    let row: ChampionScoreRow
    let name: String

    var body: some View {
        let score = row.score
        GridRow {
            Text(name)
            SignedPercent(value: score.winratePoints())
            HStack(spacing: 4) {
                Text(row.games.formatted()).monospacedDigit()
                if row.isLowSample { LowSampleMark() }
            }
            Text(row.winrate.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
            SignedPercent(value: score.winrateEdge)
            Text(score.comfort.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
            PoolMark(inPool: score.inPool)
            SignedPercent(value: score.relativePerformance)
            SignedPercent(value: score.metrics.kdaVsAverage - 1)
            SignedPercent(value: score.metrics.csVsAverage - 1)
        }
    }
}

/// Green up, red down, gray level: the sign and the arrow carry it, the color only follows.
private struct SignedPercent: View {
    let value: Double

    var body: some View {
        let shown = (value * 1_000).rounded() / 1_000
        HStack(spacing: 2) {
            Image(systemName: symbol(shown))
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(
                shown.formatted(
                    .percent.precision(.fractionLength(1)).sign(
                        strategy: .always(includingZero: false))
                )
            )
            .monospacedDigit()
        }
        .foregroundStyle(shown > 0 ? .green : shown < 0 ? .red : .secondary)
    }

    private func symbol(_ value: Double) -> String {
        value > 0 ? "arrow.up" : value < 0 ? "arrow.down" : "equal"
    }
}

private struct PoolMark: View {
    let inPool: Bool

    var body: some View {
        if inPool {
            Image(systemName: "checkmark")
                .accessibilityLabel(Text("En el pool", tableName: "Profile"))
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Fuera del pool", tableName: "Profile"))
        }
    }
}

private struct LowSampleMark: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle")
            .foregroundStyle(.secondary)
            .help(Text("Muestra baja", tableName: "Profile"))
            .accessibilityLabel(Text("Muestra baja", tableName: "Profile"))
    }
}

extension Role {
    var profileLabel: LocalizedStringResource {
        switch self {
        case .top: LocalizedStringResource("TOP", table: "Profile")
        case .jungle: LocalizedStringResource("JGL", table: "Profile")
        case .middle: LocalizedStringResource("MID", table: "Profile")
        case .bottom: LocalizedStringResource("ADC", table: "Profile")
        case .utility: LocalizedStringResource("SUP", table: "Profile")
        }
    }
}

#if DEBUG
    #Preview("History") {
        ProfileScreen(model: .preview, gameData: ProfileModel.previewGameData)
            .frame(width: 860, height: 640)
    }

    #Preview("Empty") {
        ProfileScreen(
            model: ProfileModel(
                connection: DisconnectedLCUConnection(), store: UnavailablePersonalStore()),
            gameData: nil
        )
        .frame(width: 640, height: 420)
    }

    #Preview("Empty, sync failed") {
        NoHistoryView(status: .failed(.client))
            .frame(width: 640, height: 420)
    }
#endif
