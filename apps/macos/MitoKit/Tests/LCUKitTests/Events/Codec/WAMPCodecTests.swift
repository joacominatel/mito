import Foundation
import Testing

@testable import LCUKit

struct WAMPCodecTests {
    private static let session = LCUTopic.champSelectSession.rawValue

    private func event(_ frame: String) throws -> (topic: LCUTopic, event: LCUEvent) {
        guard case .event(let topic, let event) = WAMPCodec.decode(frame) else {
            Issue.record("Expected an event from \(frame)")
            throw ExpectedAnEvent()
        }
        return (topic, event)
    }

    private struct ExpectedAnEvent: Error {}

    private func json(_ data: Data) -> NSObject? {
        try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? NSObject
    }

    // MARK: Encoding

    @Test(arguments: LCUTopic.allCases)
    func subscribeFrameIsOpcodeFiveWithTheTopicName(topic: LCUTopic) throws {
        let frame = try #require(json(Data(WAMPCodec.subscribe(topic).utf8)))
        #expect(frame == [5, topic.rawValue] as NSArray)
    }

    @Test(arguments: LCUTopic.allCases)
    func unsubscribeFrameIsOpcodeSixWithTheTopicName(topic: LCUTopic) throws {
        let frame = try #require(json(Data(WAMPCodec.unsubscribe(topic).utf8)))
        #expect(frame == [6, topic.rawValue] as NSArray)
    }

    @Test func subscribeFrameIsTheCompactTextTheClientExpects() {
        #expect(
            WAMPCodec.subscribe(.gameflowPhase)
                == #"[5,"OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"]"#)
    }

    @Test(arguments: LCUTopic.allCases)
    func ownFramesDecodeAsIgnorable(topic: LCUTopic) {
        #expect(WAMPCodec.decode(WAMPCodec.subscribe(topic)) == .ignored)
        #expect(WAMPCodec.decode(WAMPCodec.unsubscribe(topic)) == .ignored)
    }

    // MARK: Decoding events

    @Test(arguments: LCUTopic.allCases)
    func eventRoundTripsTopicURIAndData(topic: LCUTopic) throws {
        let payload: [String: Any] = [
            "data": ["phase": "ChampSelect", "ids": [1, 2, 3], "nested": ["ok": true]],
            "eventType": "Update",
            "uri": "/some/uri",
        ]
        let frame = try JSONSerialization.data(withJSONObject: [8, topic.rawValue, payload])
        let decoded = try event(String(decoding: frame, as: UTF8.self))
        #expect(decoded.topic == topic)
        #expect(decoded.event.uri == "/some/uri")
        #expect(decoded.event.eventType == .update)
        #expect(json(decoded.event.data) == payload["data"] as? NSObject)
    }

    @Test(arguments: [
        ("Create", LCUEvent.EventType.create), ("Update", .update), ("Delete", .delete),
        ("Patch", .unknown("Patch")),
    ])
    func decodesTheEventType(raw: String, type: LCUEvent.EventType) throws {
        let decoded = try event(
            #"[8,"\#(Self.session)",{"data":{},"eventType":"\#(raw)","uri":"/x"}]"#)
        #expect(decoded.event.eventType == type)
    }

    @Test func keepsAScalarDataPayload() throws {
        let decoded = try event(
            #"[8,"OnJsonApiEvent_lol-gameflow_v1_gameflow-phase",{"data":"ChampSelect","eventType":"Update","uri":"/lol-gameflow/v1/gameflow-phase"}]"#
        )
        #expect(try JSONDecoder().decode(String.self, from: decoded.event.data) == "ChampSelect")
    }

    @Test func keepsLargeIntegerIDsExact() throws {
        struct Summoner: Decodable { let summonerId: Int64 }
        let decoded = try event(
            #"[8,"OnJsonApiEvent_lol-summoner_v1_current-summoner",{"data":{"summonerId":9007199254740993},"eventType":"Update","uri":"/lol-summoner/v1/current-summoner"}]"#
        )
        let summoner = try JSONDecoder().decode(Summoner.self, from: decoded.event.data)
        #expect(summoner.summonerId == 9_007_199_254_740_993)
    }

    @Test func aNullDataPayloadIsJSONNull() throws {
        let decoded = try event(
            #"[8,"\#(Self.session)",{"data":null,"eventType":"Delete","uri":"/lol-champ-select/v1/session"}]"#
        )
        #expect(decoded.event.eventType == .delete)
        #expect(String(decoding: decoded.event.data, as: UTF8.self) == "null")
    }

    @Test func aMissingDataPayloadIsJSONNull() throws {
        let decoded = try event(#"[8,"\#(Self.session)",{"eventType":"Delete","uri":"/x"}]"#)
        #expect(String(decoding: decoded.event.data, as: UTF8.self) == "null")
    }

    @Test func toleratesExtraKeysAndExtraElements() throws {
        let decoded = try event(
            #"[8,"\#(Self.session)",{"data":{"a":1},"eventType":"Create","uri":"/x","new":true},"tail"]"#
        )
        #expect(decoded.event.uri == "/x")
        #expect(json(decoded.event.data) == ["a": 1] as NSDictionary)
    }

    // MARK: Ignorable frames

    @Test(arguments: [
        #"{"opcode":8}"#,
        #""OnJsonApiEvent""#,
        "42",
        "[]",
        "[8]",
        #"[8,"\#(session)"]"#,
        "not json",
        "",
        #"[8,"\#(session)",{"data":{},"eventType":"Upd"#,
    ])
    func malformedFramesAreIgnored(frame: String) {
        #expect(WAMPCodec.decode(frame) == .ignored)
    }

    @Test(arguments: [#""8""#, "true", "null", "8.5", "[8]"])
    func aWrongTypedOpcodeIsIgnored(opcode: String) {
        let frame = #"[\#(opcode),"\#(Self.session)",{"data":{},"eventType":"Update","uri":"/x"}]"#
        #expect(WAMPCodec.decode(frame) == .ignored)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5, 6, 7, 9, 99])
    func opcodesOtherThanEightAreIgnored(opcode: Int) {
        let frame = #"[\#(opcode),"\#(Self.session)",{"data":{},"eventType":"Update","uri":"/x"}]"#
        #expect(WAMPCodec.decode(frame) == .ignored)
    }

    @Test(arguments: ["OnJsonApiEvent", "OnJsonApiEvent_lol-chat_v1_me", ""])
    func unknownTopicsAreIgnored(topic: String) {
        let frame = #"[8,"\#(topic)",{"data":{},"eventType":"Update","uri":"/x"}]"#
        #expect(WAMPCodec.decode(frame) == .ignored)
    }

    @Test(arguments: [
        #"{"data":{},"eventType":"Update"}"#,
        #"{"data":{},"uri":"/x"}"#,
        #"{"data":{},"eventType":1,"uri":"/x"}"#,
        #"{"data":{},"eventType":"Update","uri":null}"#,
        #"["data"]"#,
        "null",
    ])
    func anEventWithoutAUsablePayloadIsIgnored(payload: String) {
        #expect(WAMPCodec.decode(#"[8,"\#(Self.session)",\#(payload)]"#) == .ignored)
    }
}
