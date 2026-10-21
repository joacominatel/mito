import MitoCore
import SwiftUI

/// The "Campeones" destination (§22.2); the shell builds it without arguments.
struct ChampionsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ChampionsScreen(model: app.champions)
    }
}

struct ChampionsScreen: View {
    @Bindable var model: ChampionsModel

    var body: some View {
        NavigationStack {
            Group {
                if let meta = model.meta {
                    TierList(model: model, meta: meta)
                } else {
                    NoStatsView()
                }
            }
            .navigationDestination(item: $model.openedChampion) { champion in
                ChampionPage(
                    name: model.championName(champion), roles: model.roles(of: champion))
            }
        }
    }
}

private struct TierList: View {
    @Bindable var model: ChampionsModel
    let meta: SnapshotMeta
    @State private var selection: ChampionID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                "Parche \(meta.patch.rawValue) · \(meta.matches.formatted()) partidas",
                tableName: "Champions"
            )
            .font(.headline)
            .padding()
            Table(model.rows, selection: $selection) {
                TableColumn(Text("Tier", tableName: "Champions")) { row in
                    TierBadge(tier: row.tier)
                }
                .width(44)
                TableColumn(Text("Campeón", tableName: "Champions")) { row in
                    HStack(spacing: 6) {
                        ChampionIcon(id: row.champion, size: 20)
                        Text(row.name)
                    }
                }
                TableColumn(Text("WR", tableName: "Champions")) { row in
                    PercentText(value: row.winrate)
                }
                .width(min: 60, ideal: 70)
                TableColumn(Text("PR", tableName: "Champions")) { row in
                    PercentText(value: row.pickRate)
                }
                .width(min: 60, ideal: 70)
                TableColumn(Text("Partidas", tableName: "Champions")) { row in
                    GamesText(games: row.games, isLowSample: row.isLowSample)
                }
                .width(min: 80, ideal: 100)
            }
            .contextMenu(forSelectionType: ChampionID.self) { _ in
            } primaryAction: { champions in
                model.openedChampion = champions.first
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(selection: $model.role) {
                    ForEach(Role.allCases, id: \.self) { role in
                        Text(role.tierListLabel).tag(role)
                    }
                } label: {
                    Text("Rol", tableName: "Champions")
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct NoStatsView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sin estadísticas todavía", tableName: "Champions")
            } icon: {
                Image(systemName: "chart.bar.xaxis")
            }
        } description: {
            Text(
                "Mito todavía no descargó los datos del parche. Mientras tanto funcionan el auto-accept, las páginas fijas por campeón y tu historial.",
                tableName: "Champions")
        }
    }
}

/// A simple page for one champion: its stats in every role it is played in.
struct ChampionPage: View {
    let name: String
    let roles: [ChampionRoleRow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    if roles.isEmpty {
                        Text("Sin estadísticas para este campeón", tableName: "Champions")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        RoleStatsGrid(roles: roles)
                    }
                } label: {
                    Text("Por rol", tableName: "Champions")
                }
                GroupBox {
                    Label {
                        Text(
                            "La build recomendada va a aparecer acá.", tableName: "Champions")
                    } icon: {
                        Image(systemName: "hammer")
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Build recomendada", tableName: "Champions")
                }
            }
            .padding()
        }
        .navigationTitle(name)
    }
}

private struct RoleStatsGrid: View {
    let roles: [ChampionRoleRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Rol", tableName: "Champions")
                Text("Tier", tableName: "Champions")
                Text("WR", tableName: "Champions")
                Text("PR", tableName: "Champions")
                Text("Partidas", tableName: "Champions")
            }
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            ForEach(roles, id: \.role) { row in
                GridRow {
                    Text(row.role.tierListLabel)
                    TierBadge(tier: row.tier)
                    PercentText(value: row.winrate)
                    PercentText(value: row.pickRate)
                    GamesText(games: row.games, isLowSample: row.isLowSample)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The letter always carries the tier; the color only reinforces it.
private struct TierBadge: View {
    let tier: Tier?

    var body: some View {
        if let tier {
            Text(verbatim: tier.rawValue)
                .font(.callout.bold())
                .frame(minWidth: 22)
                .padding(.vertical, 1)
                .foregroundStyle(color(for: tier))
                .background(color(for: tier).opacity(0.15), in: .rect(cornerRadius: 4))
                .accessibilityLabel(Text("Tier \(tier.rawValue)", tableName: "Champions"))
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Sin tier", tableName: "Champions"))
        }
    }

    private func color(for tier: Tier) -> Color {
        switch tier {
        case .s: .green
        case .a: .mint
        case .b: .secondary
        case .c: .orange
        case .d: .red
        }
    }
}

private struct PercentText: View {
    let value: Double

    var body: some View {
        Text(value.formatted(.percent.precision(.fractionLength(1))))
            .monospacedDigit()
    }
}

private struct GamesText: View {
    let games: Int
    let isLowSample: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(games.formatted())
                .monospacedDigit()
            if isLowSample {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .help(Text("Muestra baja", tableName: "Champions"))
                    .accessibilityLabel(Text("Muestra baja", tableName: "Champions"))
            }
        }
    }
}

#if DEBUG
    #Preview("Tier list") {
        ChampionsScreen(model: .preview)
            .frame(width: 640, height: 420)
    }

    #Preview("No snapshot") {
        ChampionsScreen(model: ChampionsModel())
            .frame(width: 640, height: 420)
    }

    #Preview("Champion page") {
        let model = ChampionsModel.preview
        let ahri = ChampionID(rawValue: 103)
        return ChampionPage(name: model.championName(ahri), roles: model.roles(of: ahri))
            .frame(width: 520, height: 360)
    }
#endif
