import Foundation
import MitoTestSupport
import Testing

struct FixturesTests {
    @Test func rootIsTheRepositoryFixturesDirectory() {
        let repository = Fixtures.root.deletingLastPathComponent()
        #expect(Fixtures.root.lastPathComponent == "fixtures")
        #expect(
            FileManager.default.fileExists(
                atPath: repository.appending(path: "apps/macos/MitoKit/Package.swift").path))
    }

    @Test func urlResolvesAPathUnderTheRoot() {
        #expect(
            Fixtures.url("lcu/cases/a.json") == Fixtures.root.appending(path: "lcu/cases/a.json"))
    }
}
