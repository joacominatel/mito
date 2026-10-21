import CoreGraphics
import Foundation
import ImageIO
import LCUKit
import MitoAssets
import MitoCore
import MitoStore
import Observation
import SwiftUI

/// What a view shows an icon of. The source turns it into an `IconRequest` from the client's data.
enum GameAsset: Hashable {
    case champion(ChampionID)
    case item(ItemID)
    case perk(PerkID)
    case perkStyle(PerkStyleID)
    case spell(SummonerSpellID)
}

/// `IconLoader` in the app; a fake in tests.
nonisolated protocol IconLoading: Sendable {
    func icon(for request: IconRequest) async throws(IconError) -> Data
}

nonisolated extension IconLoader: IconLoading {}

/// `IconLoader` takes Data Dragon through its own transport protocol.
nonisolated struct DataDragonIconTransport: DataDragonTransport {
    let client: DataDragonClient

    func data(from url: URL) async throws -> Data { try await client.data(from: url) }
}

/// The app's one icon source (§9.3): client first, Data Dragon for champions and items, decoded
/// off the main actor and kept in memory in front of `IconLoader`'s disk cache. A failed icon is
/// not asked for again until the next connection.
@Observable
final class IconSource {
    private(set) var images: [IconRequest: CGImage] = [:]

    @ObservationIgnored private let connection: any LCUConnection
    @ObservationIgnored private let loader: (any IconLoading)?
    @ObservationIgnored private let gameData: @MainActor () -> GameData?
    @ObservationIgnored private let gameVersion: @MainActor () -> GameVersion?
    @ObservationIgnored private var failed: Set<IconRequest> = []
    @ObservationIgnored private var flights: [IconRequest: Task<Void, Never>] = [:]

    /// Without a loader nothing loads: previews, tests, and the app under XCTest.
    init(
        connection: any LCUConnection = DisconnectedLCUConnection(),
        loader: (any IconLoading)? = nil,
        gameData: @escaping @MainActor () -> GameData? = { nil },
        gameVersion: @escaping @MainActor () -> GameVersion? = { nil }
    ) {
        self.connection = connection
        self.loader = loader
        self.gameData = gameData
        self.gameVersion = gameVersion
    }

    /// Under XCTest there is no loader, so tests never reach the client, Data Dragon, or the cache.
    static func liveLoader(connection: any LCUConnection, underTest: Bool) -> (any IconLoading)? {
        underTest
            ? nil
            : IconLoader(
                connection: connection,
                dataDragon: DataDragonIconTransport(client: DataDragonClient()))
    }

    /// `nil` until the client's data and version are in, or when the asset has no icon.
    func request(for asset: GameAsset) -> IconRequest? {
        guard let data = gameData(), let version = gameVersion() else { return nil }
        let path: String?
        var fallback: String?
        switch asset {
        case .champion(let id):
            let champion = data.champion(id)
            path = champion?.iconPath
            fallback = champion.flatMap { $0.alias.isEmpty ? nil : "champion/\($0.alias).png" }
        case .item(let id):
            path = data.item(id)?.iconPath
            fallback = "item/\(id.rawValue).png"
        case .perk(let id): path = data.perk(id)?.iconPath
        case .perkStyle(let id): path = data.perkStyle(id)?.iconPath
        case .spell(let id): path = data.spell(id)?.iconPath
        }
        guard let path, !path.isEmpty else { return nil }
        return try? IconRequest(
            assetPath: path, gameVersion: version.rawValue,
            dataDragonURL: fallback.flatMap { Self.dataDragonURL(patch: version.patch, file: $0) })
    }

    /// Memory only; `nil` shows the placeholder.
    func image(for request: IconRequest?) -> CGImage? {
        request.flatMap { images[$0] }
    }

    /// Returns at once for an icon in memory, one that failed, or without a loader; callers of an
    /// icon already loading wait for that same load.
    func load(_ request: IconRequest) async {
        guard let loader, images[request] == nil, !failed.contains(request) else { return }
        if let flight = flights[request] { return await flight.value }
        let flight = Task {
            let image = await Self.fetch(request, from: loader)
            if let image { images[request] = image } else { failed.insert(request) }
            flights[request] = nil
        }
        flights[request] = flight
        await flight.value
    }

    /// A client that was not serving icons gets another try on each connection.
    func run() async {
        for await state in connection.states() where state == .connected {
            failed.removeAll()
        }
    }

    /// Data Dragon numbers its builds `<patch>.1`; a hotfix build just misses the fallback.
    private static func dataDragonURL(patch: Patch, file: String) -> URL? {
        guard !patch.rawValue.isEmpty else { return nil }
        return URL(
            string: "https://\(IconRequest.dataDragonHost)/cdn/\(patch.rawValue).1/img/\(file)")
    }

    @concurrent
    private static func fetch(_ request: IconRequest, from loader: any IconLoading) async
        -> CGImage?
    {
        guard let data = try? await loader.icon(for: request),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        // Decodes now, here, instead of on the main actor at first draw.
        return CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

extension EnvironmentValues {
    /// `nil` in previews that do not set it: every icon shows its placeholder.
    @Entry var iconSource: IconSource? = nil
}
