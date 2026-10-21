import MitoCore
import MitoEngine
import SwiftUI

/// The "Mi historial" tab of the analysis panel (§20.2): your games with your champion, against
/// your lane rival, and in your role. Works without a snapshot (§20.3).
struct HistoryTab: View {
    let summary: HistorySummary

    init(subject: AnalysisSubject) {
        summary = HistorySummary(subject: subject)
    }

    var body: some View {
        switch summary.content {
        case .noHistory:
            Empty(
                symbol: "clock.arrow.circlepath",
                title: Text("Todavía no hay partidas tuyas", tableName: "History"),
                description: Text(
                    "Mito las lee del historial del cliente al abrirse y se suman al terminar cada partida.",
                    tableName: "History"))
        case .noChampion:
            Empty(
                symbol: "person.crop.circle.badge.questionmark",
                title: Text("Sin campeón todavía", tableName: "History"),
                description: Text(
                    "Aparece cuando lockeás o hacés hover sobre un campeón.", tableName: "History"
                ))
        case .blocks(let blocks):
            VStack(alignment: .leading, spacing: 12) {
                if !summary.notes.isEmpty {
                    Notes(notes: summary.notes)
                }
                HStack(alignment: .top, spacing: 20) {
                    ForEach(blocks) { block in
                        BlockView(block: block)
                    }
                }
            }
        }
    }
}

private struct Empty: View {
    let symbol: String
    let title: Text
    let description: Text

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: symbol)
            }
        } description: {
            description
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct Notes: View {
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(notes, id: \.self) { note in
                Label {
                    Text(verbatim: note)
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// One VoiceOver element per block: its title, then each row.
private struct BlockView: View {
    let block: HistorySummary.Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: block.title)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: block.kind.symbol)
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
            if let empty = block.empty {
                Text(verbatim: empty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !block.rows.isEmpty {
                Grid(
                    alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4
                ) {
                    ForEach(block.rows) { row in
                        GridRow {
                            Text(verbatim: row.label)
                                .foregroundStyle(.secondary)
                            Text(verbatim: row.value)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

extension HistorySummary.Block.Kind {
    fileprivate var symbol: String {
        switch self {
        case .champion: "person.crop.circle"
        case .opponent: "person.2"
        case .role: "map"
        }
    }
}

// MARK: Previews

#Preview("Con historial") {
    HistoryTab(subject: HistoryPreview.subject())
        .padding()
        .frame(width: 900)
}

#Preview("Pick recomendado, rival probable") {
    HistoryTab(
        subject: HistoryPreview.subject(
            champion: .init(id: HistoryPreview.syndra, source: .recommended),
            rival: .inferred(.middle, probability: 0.82))
    )
    .padding()
    .frame(width: 900)
}

#Preview("ARAM") {
    HistoryTab(subject: HistoryPreview.subject(queue: .aram, role: nil))
        .padding()
        .frame(width: 900)
}

#Preview("Sin historial") {
    HistoryTab(subject: HistoryPreview.subject(matches: []))
        .padding()
        .frame(width: 900)
}

private enum HistoryPreview {
    static let ahri = ChampionID(rawValue: 103)
    static let syndra = ChampionID(rawValue: 134)
    static let zed = ChampionID(rawValue: 238)

    static func subject(
        queue: QueueType = .rankedSolo, role: Role? = .middle,
        champion: AnalysisSubject.Champion = .init(id: ahri, source: .locked),
        rival: AnalysisSubject.SlotRole = .assigned(.middle), matches: [MyMatch]? = nil
    ) -> AnalysisSubject {
        AnalysisSubject(
            queue: queue, champion: champion, role: role,
            laneOpponent: role == nil ? nil : .init(cellId: 5, champion: zed, role: rival),
            allies: [], enemies: [], stats: ChampSelectModel.NoStats(),
            personal: PersonalInputs(
                matches: matches ?? games(queue: queue), masteryPoints: [ahri: 182_340]),
            names: ReasonNames(
                champion: { [103: "Ahri", 134: "Syndra", 238: "Zed"][$0.rawValue] ?? "?" },
                item: { _ in "" }),
            gameData: nil)
    }

    private static func games(queue: QueueType) -> [MyMatch] {
        (0..<14).map { index in
            MyMatch(
                game: GameID(rawValue: index), queue: queue.queueID,
                patch: Patch(rawValue: "16.21"),
                playedAt: .now.addingTimeInterval(Double(-index) * 86_400 * 2),
                champion: index % 4 == 3 ? syndra : ahri,
                role: queue == .aram ? nil : (index % 5 == 4 ? .top : .middle),
                win: index % 3 != 0, kills: 6 + index % 4, deaths: 3 + index % 3,
                assists: 7, cs: 190 + index * 3, durationSeconds: 1_700 + index * 30,
                opponent: index < 3 ? zed : nil,
                spells: SpellPair(
                    first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
                perks: [], items: [], participants: [])
        }
    }
}
