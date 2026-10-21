import Foundation
import MitoCore
import MitoImport

/// One finished import, as the toast and the notification show it.
struct ImportOutcome: Identifiable, Equatable {
    enum Status: Equatable {
        case imported
        case needsConfirmation(pageID: Int, pageName: String)
        case failed
        /// Every part was skipped: nothing to tell the user.
        case unchanged
    }

    /// Why the loadout's item set was left out before reaching the importer.
    enum ItemsUnavailable: Equatable {
        /// Only Summoner's Rift (map 11) has a known item set map code.
        case unsupportedMap
        /// `CurrentSummoner` gave no `summonerId`.
        case noAccount
    }

    enum Part: CaseIterable {
        case runes
        case spells
        case items
    }

    enum Tone: Equatable {
        case done
        case neutral
        case attention
        case failure
    }

    struct Row: Identifiable, Equatable {
        let part: Part
        let symbol: String
        let tone: Tone
        let status: LocalizedStringResource

        var id: Part { part }
    }

    let id: Int
    let champion: ChampionID
    /// `"Ahri MID"`: the rune page and item set name after `Mito · `.
    let title: String
    var report: ImportReport
    let itemsUnavailable: ItemsUnavailable?

    var status: Status {
        if case .needsConfirmation(let pageID, let pageName) = report.runes {
            return .needsConfirmation(pageID: pageID, pageName: pageName)
        }
        let results = [report.runes, report.spells, report.items]
        if results.contains(where: { if case .failed = $0 { true } else { false } }) {
            return .failed
        }
        if results.contains(.applied) { return .imported }
        return .unchanged
    }

    var needsConfirmation: Bool {
        if case .needsConfirmation = status { true } else { false }
    }

    /// The toast's heading and the notification's title.
    var headline: LocalizedStringResource {
        switch status {
        case .imported, .unchanged:
            LocalizedStringResource("Importado para \(title)", table: "Import")
        case .needsConfirmation:
            LocalizedStringResource("Confirmá las runas para \(title)", table: "Import")
        case .failed:
            LocalizedStringResource("No se pudo importar todo para \(title)", table: "Import")
        }
    }

    var rows: [Row] {
        Part.allCases.map { part in
            if part == .items, let itemsUnavailable {
                return Row(
                    part: part, symbol: "minus.circle", tone: .neutral,
                    status: itemsUnavailable.status)
            }
            return Self.row(part, result(of: part))
        }
    }

    private func result(of part: Part) -> StepResult {
        switch part {
        case .runes: report.runes
        case .spells: report.spells
        case .items: report.items
        }
    }

    private static func row(_ part: Part, _ result: StepResult) -> Row {
        switch result {
        case .applied:
            Row(
                part: part, symbol: "checkmark.circle.fill", tone: .done,
                status: LocalizedStringResource("Listo", table: "Import"))
        case .skipped(.notInLoadout):
            Row(
                part: part, symbol: "minus.circle", tone: .neutral,
                status: LocalizedStringResource("Sin recomendación", table: "Import"))
        case .skipped(.disabled):
            Row(
                part: part, symbol: "minus.circle", tone: .neutral,
                status: LocalizedStringResource("Apagado en Settings", table: "Import"))
        case .skipped(.alreadySelected):
            Row(
                part: part, symbol: "checkmark.circle", tone: .neutral,
                status: LocalizedStringResource("Ya estaban elegidos", table: "Import"))
        case .skipped(.noEditablePage):
            Row(
                part: part, symbol: "exclamationmark.triangle.fill", tone: .attention,
                status: LocalizedStringResource("No hay una página editable", table: "Import"))
        case .failed(.invalidRunePage):
            Row(
                part: part, symbol: "xmark.octagon.fill", tone: .failure,
                status: LocalizedStringResource(
                    "Página inválida para este parche, no se envió", table: "Import"))
        case .failed(.lcu):
            Row(
                part: part, symbol: "xmark.octagon.fill", tone: .failure,
                status: LocalizedStringResource("El cliente rechazó el cambio", table: "Import"))
        case .needsConfirmation(_, let pageName):
            Row(
                part: part, symbol: "questionmark.circle.fill", tone: .attention,
                status: pageName.isEmpty
                    ? LocalizedStringResource("¿Reemplazar tu página actual?", table: "Import")
                    : LocalizedStringResource("¿Reemplazar «\(pageName)»?", table: "Import"))
        }
    }
}

extension ImportOutcome.Part {
    var title: LocalizedStringResource {
        switch self {
        case .runes: LocalizedStringResource("Runas", table: "Import")
        case .spells: LocalizedStringResource("Spells", table: "Import")
        case .items: LocalizedStringResource("Ítems", table: "Import")
        }
    }
}

extension ImportOutcome.ItemsUnavailable {
    fileprivate var status: LocalizedStringResource {
        switch self {
        case .unsupportedMap:
            LocalizedStringResource("No disponible en este mapa", table: "Import")
        case .noAccount:
            LocalizedStringResource("No se pudo leer tu cuenta", table: "Import")
        }
    }
}
