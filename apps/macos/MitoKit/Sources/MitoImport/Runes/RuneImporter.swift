public import LCUKit
public import MitoCore

public enum RuneImportResult: Equatable, Sendable {
    /// A new Mito page, made current.
    case created
    /// The existing Mito page, or the reserved page, overwritten and made current.
    case updated(pageID: Int)
    /// The current page, overwritten under `.currentPage` or after the user confirmed it.
    case replacedCurrentPage(pageID: Int)
    /// No free slot, no Mito page, and the current page is the user's: nothing was sent. Pass
    /// `pageID` back as `confirmedReplacement` once the user accepts overwriting it.
    case needsConfirmation(pageID: Int, pageName: String)
    /// Nothing Mito may write to: the reserved page is missing or locked, or the current page
    /// is one of the client's non-editable pages.
    case noEditablePage
    /// Nothing was sent.
    case invalid(RunePageValidationError)
    /// `ImportSettings.importRunes` is off.
    case disabled
    case failed(LCUError)
}

/// Puts a recommended rune page in the client (`MITO_CONTEXT.md` §13.2).
public struct RuneImporter: Sendable {
    static let namePrefix = "Mito ·"

    private let connection: any LCUConnection

    public init(connection: any LCUConnection) {
        self.connection = connection
    }

    /// The page is named `Mito · <title>`, e.g. `title: "Ahri MID vs Zed"`. Nothing is retried.
    public func apply(
        _ page: RunePage, title: String, settings: ImportSettings,
        confirmedReplacement: Int? = nil
    ) async -> RuneImportResult {
        guard settings.importRunes else { return .disabled }
        let name = "\(Self.namePrefix) \(title)"
        do {
            let styles = try await connection.send(.perkStyles).styles
            if let error = page.validationError(against: styles) { return .invalid(error) }
            let pages = try await connection.send(.perkPages)
            switch try await target(in: pages, settings, confirmedReplacement) {
            case .create:
                _ = try await connection.send(.createPerkPage(page, name: name))
                return .created
            case .update(let id):
                _ = try await connection.send(.updatePerkPage(id: id, page, name: name))
                return .updated(pageID: id)
            case .replaceCurrent(let id):
                _ = try await connection.send(.updatePerkPage(id: id, page, name: name))
                return .replacedCurrentPage(pageID: id)
            case .none(let result):
                return result
            }
        } catch {
            return .failed(error)
        }
    }

    private enum Target {
        case create
        case update(Int)
        case replaceCurrent(Int)
        case none(RuneImportResult)
    }

    private func target(
        in pages: [PerkPage], _ settings: ImportSettings, _ confirmedReplacement: Int?
    ) async throws(LCUError) -> Target {
        let editable = pages.filter { $0.isEditable == true }
        let current = editable.first { $0.current == true }
        switch settings.runePageTarget {
        case .reservedPage:
            guard let id = settings.reservedRunePageID, editable.contains(where: { $0.id == id })
            else { return .none(.noEditablePage) }
            return .update(id)
        case .currentPage:
            guard let current else { return .none(.noEditablePage) }
            return .replaceCurrent(current.id)
        case .mitoPage:
            let mitoPages = editable.filter { $0.name?.hasPrefix(Self.namePrefix) == true }
            if let mito = mitoPages.first(where: { $0.current == true }) ?? mitoPages.first {
                return .update(mito.id)
            }
            let owned = try await connection.send(.perkInventory).ownedPageCount ?? 0
            // Unknown flags count as custom: a wrong guess asks the user instead of a failed POST.
            if pages.count(where: { $0.isDeletable != false }) < owned { return .create }
            guard let current else { return .none(.noEditablePage) }
            if current.id == confirmedReplacement { return .replaceCurrent(current.id) }
            return .none(.needsConfirmation(pageID: current.id, pageName: current.name ?? ""))
        }
    }
}
