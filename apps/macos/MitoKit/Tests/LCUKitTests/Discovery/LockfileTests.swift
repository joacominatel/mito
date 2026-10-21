import Testing

@testable import LCUKit

struct LockfileTests {
    @Test func readsPortAndPassword() {
        let found = Lockfile.credentials(fromContents: "LeagueClient:1234:54321:AbCdEf123:https")
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test func surroundingWhitespaceIsIgnored() {
        let found = Lockfile.credentials(fromContents: "LeagueClient:1234:54321:AbCdEf123:https\n")
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test(arguments: [
        "", "LeagueClient", "LeagueClient:1234:54321", "LeagueClient:1234:54321:AbCdEf123",
    ])
    func partialLockfileYieldsNothing(_ contents: String) {
        #expect(Lockfile.credentials(fromContents: contents) == nil)
    }

    @Test func nonNumericPortYieldsNothing() {
        #expect(Lockfile.credentials(fromContents: "LeagueClient:1234:port:AbCdEf123:https") == nil)
    }

    @Test func emptyPasswordYieldsNothing() {
        #expect(Lockfile.credentials(fromContents: "LeagueClient:1234:54321::https") == nil)
    }

    @Test func emptyFieldsDoNotShiftThePort() {
        #expect(
            Lockfile.credentials(fromContents: "LeagueClient::54321:AbCdEf123:https")?.port
                == 54_321)
    }
}
