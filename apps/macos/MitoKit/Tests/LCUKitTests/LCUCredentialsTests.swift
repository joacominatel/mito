import Foundation
import Testing

@testable import LCUKit

struct LCUCredentialsTests {
    private let credentials = LCUCredentials(port: 54_321, token: "AbCdEf123-secret")

    @Test func descriptionRedactsTheToken() {
        #expect(!"\(credentials)".contains("AbCdEf123"))
        #expect(!String(describing: credentials).contains("AbCdEf123"))
        #expect("\(credentials)".contains("54321"))
    }

    @Test func debugDescriptionRedactsTheToken() {
        #expect(!String(reflecting: credentials).contains("AbCdEf123"))
    }

    @Test func dumpRedactsTheToken() {
        var output = ""
        dump(credentials, to: &output)
        #expect(!output.contains("AbCdEf123"))
    }

    @Test func authHeaderIsBasicAuthAsRiot() {
        let encoded = Data("riot:AbCdEf123-secret".utf8).base64EncodedString()
        #expect(credentials.authHeader == "Basic \(encoded)")
    }
}
