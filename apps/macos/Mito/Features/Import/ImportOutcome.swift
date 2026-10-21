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
        /// No snapshot is open, so nothing was imported (§20.3).
        case noStats
    }

    /// Why the loadout's item set was left out before reaching the importer.
    enum ItemsUnavailable: Equatable {
        /// Only Summoner's Rift (map 11) has a known item set map code.
        case unsupportedMap
        /// `CurrentSummoner` gave no `summonerId`.
        case noAccount
        /// The champion's override says not to import an item set (§21.5).
        case skippedByOverride
    }

    /// Where a part's choice came from, when it was not the engine's general loadout alone.
    enum Origin: Equatable {
        /// The override's fixed page, spells, or set, or its "no importar".
        case override
        /// A fixed choice was asked for but none is saved: the general one went instead.
        case noFixedChoice
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
        /// The recommendation in effect is short of reliable (§17, §18.2).
        var isLowSample = false
        var origin: Origin?

        var id: Part { part }
    }

    let id: Int
    let champion: ChampionID
    /// `"Ahri MID"`: the rune page and item set name after `Mito · `.
    let title: String
    var report: ImportReport
    let itemsUnavailable: ItemsUnavailable?
    /// Parts whose recommendation is "muestra baja".
    var lowSample: Set<Part> = []
    var origins: [Part: Origin] = [:]
    var isMissingStats = false

    var status: Status {
        if isMissingStats { return .noStats }
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
        case .noStats:
            LocalizedStringResource(
                "Sin estadísticas del parche: no se importó nada para \(title)", table: "Import")
        }
    }

    var rows: [Row] {
        guard !isMissingStats else { return [] }
        return Part.allCases.map { part in
            if part == .items, let itemsUnavailable {
                return Row(
                    part: part, symbol: "minus.circle", tone: .neutral,
                    status: itemsUnavailable.status, origin: origins[part])
            }
            let result = result(of: part)
            var row = Self.row(part, result)
            row.isLowSample = lowSample.contains(part) && result.keepsTheRecommendation
            row.origin = origins[part]
            return row
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
        case .failed(.invalidRunePage(let error)):
            Row(
                part: part, symbol: "xmark.octagon.fill", tone: .failure,
                status: LocalizedStringResource(
                    "Página inválida (\(String(localized: error.reason))), no se envió",
                    table: "Import"))
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

extension ImportOutcome {
    /// One `import_log` entry per part (§17), with codes for a detail: never a name or an account.
    func logEntries(_ parts: [Part], at date: Date) -> [ImportLogEntry] {
        parts.map { part in
            let (outcome, reason): (ImportLogEntry.Outcome, String?) =
                if part == .items, let itemsUnavailable {
                    (.skipped, itemsUnavailable.logCode)
                } else {
                    result(of: part).logged
                }
            let detail = [reason, origins[part]?.logCode].compactMap(\.self)
            return ImportLogEntry(
                timestamp: date, game: nil, champion: champion, part: part.logged,
                outcome: outcome, detail: detail.isEmpty ? nil : detail.joined(separator: ","))
        }
    }
}

extension ImportOutcome.Part {
    fileprivate var logged: ImportLogEntry.Part {
        switch self {
        case .runes: .runes
        case .spells: .spells
        case .items: .items
        }
    }
}

extension ImportOutcome.ItemsUnavailable {
    fileprivate var logCode: String? {
        switch self {
        case .unsupportedMap: "unsupported_map"
        case .noAccount: "no_account"
        // The origin already says "override".
        case .skippedByOverride: nil
        }
    }
}

extension ImportOutcome.Origin {
    fileprivate var logCode: String {
        switch self {
        case .override: "override"
        case .noFixedChoice: "no_fixed_choice"
        }
    }
}

extension StepResult {
    fileprivate var logged: (ImportLogEntry.Outcome, String?) {
        switch self {
        case .applied: (.applied, nil)
        case .skipped(.notInLoadout): (.skipped, "not_in_loadout")
        case .skipped(.disabled): (.skipped, "disabled")
        case .skipped(.alreadySelected): (.skipped, "already_selected")
        case .skipped(.noEditablePage): (.skipped, "no_editable_page")
        case .needsConfirmation: (.skipped, "needs_confirmation")
        case .failed(.invalidRunePage): (.failed, "invalid_rune_page")
        case .failed(.lcu): (.failed, "lcu")
        }
    }

    /// The recommendation is what the client holds, or what the user is asked to accept.
    fileprivate var keepsTheRecommendation: Bool {
        switch self {
        case .applied, .skipped(.alreadySelected), .needsConfirmation: true
        case .skipped, .failed: false
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
        case .skippedByOverride:
            LocalizedStringResource("No se importan", table: "Import")
        }
    }
}

extension ImportOutcome.Origin {
    var marker: LocalizedStringResource {
        switch self {
        case .override: LocalizedStringResource("· override", table: "Import")
        case .noFixedChoice:
            LocalizedStringResource("· sin fija guardada, va la general", table: "Import")
        }
    }
}

extension RunePageValidationError {
    /// Why the client would reject the page, short enough for a toast row.
    fileprivate var reason: LocalizedStringResource {
        switch self {
        case .wrongPerkCount(let count):
            LocalizedStringResource("tiene \(count) runas y no 9", table: "Import")
        case .sameStyleTwice:
            LocalizedStringResource("repite la rama", table: "Import")
        case .unknownStyle:
            LocalizedStringResource("una rama ya no existe", table: "Import")
        case .unexpectedStyleLayout:
            LocalizedStringResource("una rama cambió de forma", table: "Import")
        case .perkOutOfPlace(let index, _):
            LocalizedStringResource("la runa \(index + 1) ya no va ahí", table: "Import")
        case .secondaryPerksShareARow:
            LocalizedStringResource("las secundarias comparten fila", table: "Import")
        }
    }
}
