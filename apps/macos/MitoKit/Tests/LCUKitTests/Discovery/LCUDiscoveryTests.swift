import Foundation
import Synchronization
import Testing

@testable import LCUKit

struct LCUDiscoveryTests {
    private static let league =
        "/Applications/League of Legends.app/Contents/LoL/LeagueClient.app/Contents/LeagueClientUx.app/Contents/MacOS/LeagueClientUx"
    private static let processLine = "\(league) --app-port=54321 --remote-auth-token=FromProcess"
    private static let lockfile = "LeagueClient:1234:61000:FromLockfile:https"

    private func discovery(
        processes: [String], lockfile: String?, installPath: String? = nil
    ) -> LCUDiscovery {
        LCUDiscovery(
            installPath: installPath,
            commandLines: { processes },
            readFile: { _ in lockfile })
    }

    @Test func processArgumentsWinOverTheLockfile() async {
        let found = await discovery(processes: [Self.processLine], lockfile: Self.lockfile)
            .discover()
        #expect(found == LCUCredentials(port: 54_321, token: "FromProcess"))
    }

    @Test func fallsBackToTheLockfileWhenNoProcessCarriesCredentials() async {
        let found = await discovery(
            processes: ["/sbin/launchd", "\(Self.league) --app-pid=1234"], lockfile: Self.lockfile
        ).discover()
        #expect(found == LCUCredentials(port: 61_000, token: "FromLockfile"))
    }

    @Test func firstCompleteCandidateWinsAmongSeveral() async {
        let processes = [
            "\(Self.league) --app-port=11111",
            "/Users/Shared/Riot Games/Riot Client.app/Contents/MacOS/RiotClientServices --app-port=22222 --remote-auth-token=RiotClient",
            "\(Self.league) --app-port=33333 --remote-auth-token=First",
            "\(Self.league) --app-port=44444 --remote-auth-token=Second",
        ]
        let found = await discovery(processes: processes, lockfile: nil).discover()
        #expect(found == LCUCredentials(port: 33_333, token: "First"))
    }

    @Test func reportsNotFoundWhenNoClientIsRunning() async {
        #expect(await discovery(processes: ["/sbin/launchd"], lockfile: nil).discover() == nil)
    }

    @Test func reportsNotFoundWhenTheLockfileIsMalformed() async {
        #expect(await discovery(processes: [], lockfile: "LeagueClient:1234").discover() == nil)
    }

    @Test func readsTheLockfileOfTheDefaultInstall() async {
        let requested = Mutex<URL?>(nil)
        let discovery = LCUDiscovery(
            commandLines: { [] },
            readFile: { url in
                requested.withLock { $0 = url }
                return nil
            })
        _ = await discovery.discover()
        #expect(
            requested.withLock { $0 }?.path(percentEncoded: false)
                == "/Applications/League of Legends.app/Contents/LoL/lockfile")
    }

    @Test func aConfiguredInstallPathMovesTheLockfile() {
        let discovery = discovery(
            processes: [], lockfile: nil, installPath: "/Volumes/Games/LoL.app")
        #expect(
            discovery.lockfileURL.path(percentEncoded: false)
                == "/Volumes/Games/LoL.app/Contents/LoL/lockfile")
    }

    @Test func discoveredCredentialsNeverRenderTheToken() async throws {
        let found = try #require(
            await discovery(processes: [Self.processLine], lockfile: nil).discover())
        var dumped = ""
        dump(found, to: &dumped)
        for rendered in [String(describing: found), String(reflecting: found), dumped] {
            #expect(!rendered.contains("FromProcess"))
        }
    }

    @Test func liveProcessListingIncludesThisProcess() async {
        let lines = await LCUDiscovery.runningCommandLines()
        let me = ProcessInfo.processInfo.processName
        #expect(lines.contains { $0.contains(me) })
    }

    @Test func liveFileReadReturnsContentsOrNothing() async throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "lockfile-\(UUID().uuidString)")
        try Self.lockfile.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await LCUDiscovery.contents(of: url) == Self.lockfile)
        #expect(await LCUDiscovery.contents(of: url.appending(path: "missing")) == nil)
    }
}
