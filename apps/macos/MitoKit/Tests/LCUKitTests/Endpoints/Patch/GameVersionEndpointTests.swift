import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/session/\(name).json"))
}

private func decode(_ json: String) throws(LCUError) -> GameVersion {
    try LCUEndpoint.gameVersion.decode(Data(json.utf8))
}

private func isDecodingError(_ body: Data) -> Bool {
    do {
        _ = try LCUEndpoint.gameVersion.decode(body)
        return false
    } catch {
        guard case .decoding = error else { return false }
        return true
    }
}

private func isDecodingError(_ json: String) -> Bool { isDecodingError(Data(json.utf8)) }

struct GameVersionEndpointTests {
    @Test func isABodylessGetOnTheGameVersionPath() {
        #expect(LCUEndpoint.gameVersion.method == .get)
        #expect(LCUEndpoint.gameVersion.path == "/lol-patch/v1/game-version")
        #expect(LCUEndpoint.gameVersion.body == nil)
    }

    @Test func keepsTheFullVersionAndTakesThePatchFromItsFirstTwoComponents() throws {
        let version = try LCUEndpoint.gameVersion.decode(fixture("game-version"))
        #expect(version.rawValue == "16.21.723.1234")
        #expect(version.patch == Patch(rawValue: "16.21"))
    }

    @Test func trimsSurroundingWhitespace() throws {
        let version = try decode(#"" \n16.21.723.1234\t ""#)
        #expect(version.rawValue == "16.21.723.1234")
        #expect(version.patch == Patch(rawValue: "16.21"))
    }

    @Test func acceptsATwoComponentVersion() throws {
        let version = try decode(#""16.21""#)
        #expect(version.rawValue == "16.21")
        #expect(version.patch == Patch(rawValue: "16.21"))
    }

    @Test(arguments: [#"16.21"#, "1621", "null", #"{"version":"16.21"}"#, #"["16.21"]"#])
    func aBodyThatIsNotAStringIsADecodingError(_ json: String) {
        #expect(isDecodingError(json))
    }

    @Test func tooFewComponentsIsADecodingError() throws {
        #expect(isDecodingError(try fixture("game-version-malformed")))
    }

    @Test(arguments: [#""""#, #""   ""#, #"".21""#, #""16.""#])
    func anEmptyLeadingComponentIsADecodingError(_ json: String) {
        #expect(isDecodingError(json))
    }

    @Test(arguments: [#""16.x.723""#, #""v16.21""#, #""16.21a.723""#, #""１６.21""#])
    func aNonNumericPatchComponentIsADecodingError(_ json: String) {
        #expect(isDecodingError(json))
    }

    // Mirrors IconRequest's game-version rule, which LCUKitTests cannot import.
    @Test(arguments: [#""16.21.723/../x""#, #""16.21 723""#, #""16.21.723-a/b+branch""#])
    func aVersionThatIsNotADirectoryNameIsADecodingError(_ json: String) {
        #expect(isDecodingError(json))
    }

    @Test func dropsTheBuildMetadataAfterAPlus() throws {
        let version = try decode(#""16.21.8298620+branch.releases-16-21.code.public/x""#)
        #expect(version.rawValue == "16.21.8298620")
        #expect(version.patch == Patch(rawValue: "16.21"))
    }

    @Test func aVersionThatIsOnlyBuildMetadataIsADecodingError() {
        #expect(isDecodingError(#""+branch.releases-16-21""#))
    }

    @Test func toleratesABuildSuffixOfSafeCharacters() throws {
        let version = try decode(#""16.21.723.1234-hotfix_2""#)
        #expect(version.rawValue == "16.21.723.1234-hotfix_2")
        #expect(version.patch == Patch(rawValue: "16.21"))
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(method: .get, path: "/lol-patch/v1/game-version", json: #""16.21.723.1234""#)
        ])
        let version = try await connection.send(.gameVersion)
        #expect(version.patch == Patch(rawValue: "16.21"))
        #expect(connection.requests.map(\.path) == ["/lol-patch/v1/game-version"])
    }
}
