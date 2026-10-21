import Foundation
import LCUKit
import MitoTestSupport
import Testing

@testable import MitoAssets

struct IconLoaderTests {
    private static let path = "/lol-game-data/assets/v1/champion-icons/103.png"
    private static let dataDragonURL = URL(
        string: "https://ddragon.leagueoflegends.com/cdn/16.21.1/img/champion/Ahri.png")

    private static func request(version: String = "16.21.1", dataDragon: Bool = false) throws
        -> IconRequest
    {
        try IconRequest(
            assetPath: path, gameVersion: version, dataDragonURL: dataDragon ? dataDragonURL : nil)
    }

    private static func client(serving body: Data = pngIcon) -> FakeLCUConnection {
        FakeLCUConnection(responses: [.init(method: .get, path: path, body: body)])
    }

    private static func loader(
        _ connection: FakeLCUConnection, dataDragon: FakeDataDragon? = nil, base: URL,
        bundleIdentifier: String = testBundleIdentifier
    ) -> IconLoader {
        IconLoader(
            connection: connection, dataDragon: dataDragon, bundleIdentifier: bundleIdentifier,
            baseDirectory: base)
    }

    @Test func aClientIconIsFetchedFromItsAssetPathAndCached() async throws {
        try await withTemporaryDirectory { base in
            let connection = Self.client()
            let loader = Self.loader(connection, base: base)
            let request = try Self.request()

            #expect(try await loader.icon(for: request) == pngIcon)
            #expect(
                connection.requests == [.init(method: .get, path: Self.path, body: nil)])
            #expect(try Data(contentsOf: loader.cacheFile(for: request)) == pngIcon)
        }
    }

    @Test func aCachedIconIsServedWithoutAnyFetch() async throws {
        try await withTemporaryDirectory { base in
            let request = try Self.request(dataDragon: true)
            _ = try await Self.loader(Self.client(), base: base).icon(for: request)

            let offline = FakeLCUConnection()
            let dataDragon = FakeDataDragon()
            let reopened = Self.loader(offline, dataDragon: dataDragon, base: base)

            #expect(try await reopened.icon(for: request) == pngIcon)
            #expect(offline.requests.isEmpty)
            #expect(dataDragon.urls.isEmpty)
        }
    }

    @Test func aNewGameVersionMissesTheCacheAndFetchesFreshArt() async throws {
        try await withTemporaryDirectory { base in
            let current = try Self.request()
            let next = try Self.request(version: "16.22.1")
            _ = try await Self.loader(Self.client(), base: base).icon(for: current)

            let connection = Self.client(serving: otherPNGIcon)
            let loader = Self.loader(connection, base: base)

            #expect(try await loader.icon(for: next) == otherPNGIcon)
            #expect(connection.requests.count == 1)
            #expect(try await loader.icon(for: current) == pngIcon)
        }
    }

    @Test func aFailedClientFetchFallsBackToDataDragonAndCachesIt() async throws {
        try await withTemporaryDirectory { base in
            let dataDragon = FakeDataDragon(answer: .success(otherPNGIcon))
            let loader = Self.loader(FakeLCUConnection(), dataDragon: dataDragon, base: base)
            let request = try Self.request(dataDragon: true)

            #expect(try await loader.icon(for: request) == otherPNGIcon)
            #expect(dataDragon.urls == [Self.dataDragonURL].compactMap { $0 })
            #expect(try Data(contentsOf: loader.cacheFile(for: request)) == otherPNGIcon)
        }
    }

    @Test func aClientAnswerThatIsNotAnImageFallsBackToDataDragon() async throws {
        try await withTemporaryDirectory { base in
            let dataDragon = FakeDataDragon()
            let loader = Self.loader(
                Self.client(serving: Data(#"{"httpStatus":404}"#.utf8)), dataDragon: dataDragon,
                base: base)

            let request = try Self.request(dataDragon: true)

            #expect(try await loader.icon(for: request) == pngIcon)
            #expect(dataDragon.urls.count == 1)
        }
    }

    @Test func withoutADataDragonURLAFailedClientFetchIsReported() async throws {
        try await withTemporaryDirectory { base in
            let dataDragon = FakeDataDragon()
            let loader = Self.loader(FakeLCUConnection(), dataDragon: dataDragon, base: base)
            let request = try Self.request()

            await #expect(throws: IconError.unavailable(assetPath: Self.path)) {
                try await loader.icon(for: request)
            }
            #expect(dataDragon.urls.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: loader.cacheFile(for: request).path))
        }
    }

    @Test func aFailedDataDragonFallbackIsReported() async throws {
        try await withTemporaryDirectory { base in
            let loader = Self.loader(
                FakeLCUConnection(), dataDragon: FakeDataDragon(answer: .failure(.scripted)),
                base: base)
            let request = try Self.request(dataDragon: true)

            await #expect(throws: IconError.unavailable(assetPath: Self.path)) {
                try await loader.icon(for: request)
            }
        }
    }

    @Test(arguments: [Data(), Data("not an image".utf8)])
    func aCorruptOrEmptyCacheFileIsAMiss(_ contents: Data) async throws {
        try await withTemporaryDirectory { base in
            let connection = Self.client()
            let loader = Self.loader(connection, base: base)
            let request = try Self.request()
            let file = loader.cacheFile(for: request)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file)

            #expect(try await loader.icon(for: request) == pngIcon)
            #expect(connection.requests.count == 1)
            #expect(try Data(contentsOf: file) == pngIcon)
        }
    }

    @Test func concurrentRequestsForOneIconShareOneFetch() async throws {
        try await withTemporaryDirectory { base in
            let connection = FakeLCUConnection()
            let dataDragon = FakeDataDragon(gated: true)
            let loader = Self.loader(connection, dataDragon: dataDragon, base: base)
            let request = try Self.request(dataDragon: true)
            let callers = 5

            try await withThrowingTaskGroup(of: Data.self) { group in
                for _ in 0..<callers {
                    group.addTask { try await loader.icon(for: request) }
                }
                await waitUntil { await loader.callers(awaiting: request) == callers }
                dataDragon.release()

                var results: [Data] = []
                for try await data in group { results.append(data) }
                #expect(results == Array(repeating: pngIcon, count: callers))
            }
            #expect(connection.requests.count == 1)
            #expect(dataDragon.urls.count == 1)
        }
    }

    @Test func cancellingOneCallerDoesNotCancelTheSharedFetch() async throws {
        try await withTemporaryDirectory { base in
            let dataDragon = FakeDataDragon(gated: true)
            let loader = Self.loader(FakeLCUConnection(), dataDragon: dataDragon, base: base)
            let request = try Self.request(dataDragon: true)

            let cancelled = Task { try await loader.icon(for: request) }
            let kept = Task { try await loader.icon(for: request) }
            await waitUntil { await loader.callers(awaiting: request) == 2 }
            cancelled.cancel()
            dataDragon.release()

            #expect(try await kept.value == pngIcon)
            #expect(dataDragon.urls.count == 1)
        }
    }

    @Test func eachBundleIdentifierHasItsOwnCache() async throws {
        try await withTemporaryDirectory { base in
            let request = try Self.request()
            let release = Self.loader(Self.client(), base: base)
            _ = try await release.icon(for: request)

            let debug = Self.loader(
                FakeLCUConnection(), base: base, bundleIdentifier: "\(testBundleIdentifier).debug")

            await #expect(throws: IconError.unavailable(assetPath: Self.path)) {
                try await debug.icon(for: request)
            }
            #expect(release.directory != debug.directory)
        }
    }

    @Test func theCacheLivesInTheBundleIconsFolderPerVersion() throws {
        let base = URL(filePath: "/caches", directoryHint: .isDirectory)
        let loader = Self.loader(FakeLCUConnection(), base: base)
        let request = try Self.request()

        #expect(loader.directory.path() == "/caches/\(testBundleIdentifier)/icons/")
        #expect(
            loader.cacheFile(for: request).path()
                == "/caches/\(testBundleIdentifier)/icons/16.21.1/v1/champion-icons/103.png")
    }

    @Test func withoutABundleIdentifierTheFallbackNamesTheCache() {
        let loader = IconLoader(
            connection: FakeLCUConnection(), bundleIdentifier: nil,
            baseDirectory: URL(filePath: "/caches", directoryHint: .isDirectory))

        #expect(loader.directory.path() == "/caches/\(IconLoader.fallbackBundleIdentifier)/icons/")
    }
}
