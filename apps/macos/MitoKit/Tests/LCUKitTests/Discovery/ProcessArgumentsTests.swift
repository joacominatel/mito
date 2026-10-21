import Testing

@testable import LCUKit

/// Synthetic lines shaped after `MITO_CONTEXT.md` §10.1; no recording of a real client exists yet.
struct ProcessArgumentsTests {
    private static let executable =
        "/Applications/League of Legends.app/Contents/LoL/LeagueClient.app/Contents/LeagueClientUx.app/Contents/MacOS/LeagueClientUx"

    private func credentials(_ arguments: String) -> LCUCredentials? {
        ProcessArguments.credentials(fromCommandLine: "\(Self.executable) \(arguments)")
    }

    @Test func readsPortAndTokenFromKeyValueArguments() {
        let found = credentials("--app-port=54321 --remote-auth-token=AbCdEf123 --app-pid=1234")
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test func argumentOrderDoesNotMatter() {
        let found = credentials(
            "--app-pid=1234 --remote-auth-token=AbCdEf123 --locale=es_AR --app-port=54321")
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test func quotedArgumentsAreUnquoted() {
        let found = credentials(#""--remote-auth-token=AbCdEf123" --app-port="54321""#)
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test func quotedValueWithSpacesStaysOneArgument() {
        let found = credentials(
            #"--install-directory="/Applications/League of Legends.app" --app-port=54321 '--remote-auth-token=AbCdEf123'"#
        )
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test func spaceSeparatedValuesAreRead() {
        let found = credentials("--app-port 54321 --remote-auth-token AbCdEf123")
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test func riotClientArgumentsAreNotMistakenForTheLCU() {
        let found = credentials(
            "--riotclient-app-port=11111 --riotclient-auth-token=riot-client --remote-auth-token=AbCdEf123 --app-port=54321"
        )
        #expect(found == LCUCredentials(port: 54_321, token: "AbCdEf123"))
    }

    @Test func onlyRiotClientArgumentsYieldNothing() {
        #expect(
            credentials("--riotclient-app-port=11111 --riotclient-auth-token=riot-client") == nil)
    }

    @Test func missingTokenYieldsNothing() {
        #expect(credentials("--app-port=54321 --app-pid=1234") == nil)
    }

    @Test func missingPortYieldsNothing() {
        #expect(credentials("--remote-auth-token=AbCdEf123") == nil)
    }

    @Test func emptyTokenYieldsNothing() {
        #expect(credentials("--app-port=54321 --remote-auth-token=") == nil)
    }

    @Test func optionWithoutValueYieldsNothing() {
        #expect(credentials("--remote-auth-token --app-port=54321") == nil)
    }

    @Test(arguments: ["abc", "0", "70000", "-1", ""])
    func invalidPortYieldsNothing(_ port: String) {
        #expect(credentials("--app-port=\(port) --remote-auth-token=AbCdEf123") == nil)
    }

    @Test func otherProcessesWithTheSameArgumentsAreIgnored() {
        let line =
            "/Users/Shared/Riot Games/Riot Client.app/Contents/MacOS/RiotClientServices --app-port=54321 --remote-auth-token=AbCdEf123"
        #expect(ProcessArguments.credentials(fromCommandLine: line) == nil)
    }

    @Test func aLineWithoutOptionsYieldsNothing() {
        #expect(ProcessArguments.credentials(fromCommandLine: Self.executable) == nil)
    }
}
