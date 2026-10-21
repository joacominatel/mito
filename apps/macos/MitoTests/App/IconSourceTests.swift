import CoreGraphics
import Foundation
import ImageIO
import LCUKit
import MitoAssets
import MitoCore
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import Mito

@Suite(.timeLimit(.minutes(1)))
struct IconSourceTests {
    static let ahri = ChampionID(rawValue: 103)
    static let gameData = GameData(
        champions: [
            Champion(
                id: ahri, alias: "Ahri", name: "Ahri",
                iconPath: "/lol-game-data/assets/v1/champion-icons/103.png")
        ],
        items: [
            Item(
                id: ItemID(rawValue: 3020), name: "Botas del hechicero", totalGold: 1100,
                iconPath: "/lol-game-data/assets/ASSETS/Items/Icons2D/3020.png", itemClass: nil)
        ],
        perks: [Perk(id: PerkID(rawValue: 8112), name: "Electrocutar", iconPath: "")])

    // MARK: Requests

    @Test func aChampionAsksTheClientPathWithADataDragonFallback() throws {
        let request = try #require(Self.source().request(for: .champion(Self.ahri)))

        #expect(request.assetPath == "/lol-game-data/assets/v1/champion-icons/103.png")
        #expect(request.gameVersion == "16.21.723.1234")
        #expect(
            request.dataDragonURL?.absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.21.1/img/champion/Ahri.png")
    }

    @Test func anItemFallsBackToItsDataDragonImageByID() throws {
        let request = try #require(Self.source().request(for: .item(ItemID(rawValue: 3020))))

        #expect(
            request.dataDragonURL?.absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.21.1/img/item/3020.png")
    }

    @Test func noGameDataNoVersionOrNoIconPathMeansNoRequest() {
        #expect(Self.source(gameData: nil).request(for: .champion(Self.ahri)) == nil)
        #expect(Self.source(version: nil).request(for: .champion(Self.ahri)) == nil)
        #expect(Self.source().request(for: .perk(PerkID(rawValue: 8112))) == nil)
        #expect(Self.source().request(for: .champion(ChampionID(rawValue: 1))) == nil)
    }

    // MARK: Loading

    @Test func aLoadedIconIsServedFromMemoryAfterwards() async throws {
        let loader = RecordingIconLoader(answer: .success(Self.png))
        let source = Self.source(loader: loader)
        let request = try #require(source.request(for: .champion(Self.ahri)))
        #expect(source.image(for: request) == nil)

        await source.load(request)
        await source.load(request)

        #expect(source.image(for: request)?.width == 2)
        #expect(loader.calls == 1)
    }

    @Test func concurrentCallersShareOneLoad() async throws {
        let loader = RecordingIconLoader(answer: .success(Self.png))
        let source = Self.source(loader: loader)
        let request = try #require(source.request(for: .champion(Self.ahri)))

        async let first: Void = source.load(request)
        async let second: Void = source.load(request)
        _ = await (first, second)

        #expect(loader.calls == 1)
        #expect(source.image(for: request) != nil)
    }

    @Test func aFailedIconKeepsThePlaceholderAndIsNotAskedForAgain() async throws {
        let loader = RecordingIconLoader(answer: .failure(.unavailable(assetPath: "")))
        let source = Self.source(loader: loader)
        let request = try #require(source.request(for: .champion(Self.ahri)))

        await source.load(request)
        await source.load(request)

        #expect(source.image(for: request) == nil)
        #expect(loader.calls == 1)
    }

    @Test func bytesThatDoNotDecodeCountAsAFailure() async throws {
        let loader = RecordingIconLoader(answer: .success(Data("not an image".utf8)))
        let source = Self.source(loader: loader)
        let request = try #require(source.request(for: .champion(Self.ahri)))

        await source.load(request)
        await source.load(request)

        #expect(source.image(for: request) == nil)
        #expect(loader.calls == 1)
    }

    @Test func aNewConnectionRetriesWhatFailed() async throws {
        let loader = RecordingIconLoader(answer: .failure(.unavailable(assetPath: "")))
        let connection = ScriptedLCUConnection(script: [.connected])
        let source = Self.source(connection: connection, loader: loader)
        let request = try #require(source.request(for: .champion(Self.ahri)))
        await source.load(request)

        await source.run()
        await source.load(request)

        #expect(loader.calls == 2)
    }

    @Test func withoutALoaderNothingLoads() async throws {
        let source = Self.source(loader: nil)
        let request = try #require(source.request(for: .champion(Self.ahri)))

        await source.load(request)

        #expect(source.image(for: request) == nil)
    }

    @Test func underXCTestTheAppGetsNoLoader() {
        #expect(
            IconSource.liveLoader(connection: DisconnectedLCUConnection(), underTest: true) == nil)
    }

    // MARK: Fixtures

    static func source(
        connection: any LCUConnection = DisconnectedLCUConnection(),
        loader: (any IconLoading)? = nil, gameData: GameData? = gameData,
        version: String? = "16.21.723.1234"
    ) -> IconSource {
        let gameVersion = version.flatMap {
            try? JSONDecoder().decode(GameVersion.self, from: Data("\"\($0)\"".utf8))
        }
        return IconSource(
            connection: connection, loader: loader, gameData: { gameData },
            gameVersion: { gameVersion })
    }

    /// A 2×2 PNG.
    static let png: Data = {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()
}

nonisolated final class RecordingIconLoader: IconLoading {
    private let answer: Result<Data, IconError>
    private let count = Mutex(0)

    init(answer: Result<Data, IconError>) {
        self.answer = answer
    }

    var calls: Int { count.withLock { $0 } }

    func icon(for request: IconRequest) async throws(IconError) -> Data {
        count.withLock { $0 += 1 }
        return try answer.get()
    }
}
