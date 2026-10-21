import Foundation
import MitoCore
import Testing

struct RoleTests {
    @Test func encodesAsTheCanonicalSnapshotValue() throws {
        let json = try JSONEncoder().encode([Role.top, .jungle, .middle, .bottom, .utility])
        #expect(
            String(decoding: json, as: UTF8.self)
                == #"["TOP","JUNGLE","MIDDLE","BOTTOM","UTILITY"]"#)
    }

    @Test func decodesTheCanonicalSnapshotValue() throws {
        let role = try JSONDecoder().decode(Role.self, from: Data(#""UTILITY""#.utf8))
        #expect(role == .utility)
    }

    @Test(arguments: [
        ("top", Role.top), ("jungle", .jungle), ("middle", .middle), ("bottom", .bottom),
        ("utility", .utility),
    ])
    func mapsTheLowercaseLCUPosition(position: String, role: Role) {
        #expect(Role(lcuPosition: position) == role)
    }

    @Test func blindPickEmptyPositionHasNoRole() {
        #expect(Role(lcuPosition: "") == nil)
    }

    @Test func unknownLCUPositionHasNoRole() {
        #expect(Role(lcuPosition: "support") == nil)
    }

    @Test func encodesAsADictionaryKey() throws {
        let json = try JSONEncoder().encode([Role.middle: 3])
        #expect(String(decoding: json, as: UTF8.self) == #"{"MIDDLE":3}"#)
    }
}
