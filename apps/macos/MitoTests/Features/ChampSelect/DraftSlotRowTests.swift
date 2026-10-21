import Foundation
import MitoCore
import Testing

@testable import Mito

/// VoiceOver reads a slot as one line: who, role, champion, turn (§22).
struct DraftSlotRowTests {
    nonisolated private static let probable = 0.62.formatted(.percent.precision(.fractionLength(0)))

    @Test(
        arguments: [
            (
                DraftSlotRow(
                    id: 2, pick: .locked("Ahri"), role: .assigned(.middle), turn: .pick,
                    isMe: true),
                "Vos, Mid, Ahri, lockeado, Eligiendo"
            ),
            (
                DraftSlotRow(
                    id: 7, pick: .hovering("Zed"), role: .uncertain(.top), turn: .ban,
                    isMe: false),
                "Rol incierto, quizás Top, Zed, en hover, Baneando"
            ),
            (
                DraftSlotRow(
                    id: 8, pick: .locked("Lee Sin"), role: .inferred(.jungle, confidence: 0.62),
                    turn: nil, isMe: false),
                "Rol probable: Jungla, \(probable), Lee Sin, lockeado"
            ),
            (
                DraftSlotRow(id: 9, pick: .empty, role: .none, turn: nil, isMe: false),
                "Sin campeón"
            ),
        ])
    func readsTheSlotInOneLine(row: DraftSlotRow, label: String) {
        #expect(row.accessibilityLabel == label)
    }

    @Test(
        arguments: [
            (DraftSlotRow.Pick.locked("Ahri"), ChampionIcon.State.locked),
            (.hovering("Zed"), .hover),
            (.empty, .normal),
        ])
    func theIconFollowsThePick(pick: DraftSlotRow.Pick, state: ChampionIcon.State) {
        let row = DraftSlotRow(id: 0, pick: pick, role: .none, turn: nil, isMe: false)
        #expect(row.iconState == state)
    }
}
