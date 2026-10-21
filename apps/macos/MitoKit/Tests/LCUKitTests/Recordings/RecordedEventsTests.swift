import Foundation
import Testing

@testable import LCUKit

struct RecordedEventsTests {
    @Test(arguments: Recording.scenarios)
    func everyEventArrivesOnAMitoTopicWithAURIUnderItsPath(_ scenario: String) throws {
        let recording = try Recording(scenario)
        #expect(!recording.events.isEmpty)
        for recorded in recording.events {
            let topic = try #require(LCUTopic(rawValue: recorded.topic))
            let path = topic.rawValue.dropFirst("OnJsonApiEvent".count)
            #expect(recorded.event.uri.replacing("/", with: "_").hasPrefix(path))
        }
    }

    @Test(arguments: Recording.scenarios)
    func everyEventFramedAsTheClientSendsItDecodesUnchanged(_ scenario: String) throws {
        for recorded in try Recording(scenario).events {
            let data = String(decoding: recorded.event.data, as: UTF8.self)
            let eventType = try #require(Self.rawEventType(recorded.event.eventType))
            let frame =
                #"[8,"\#(recorded.topic)",{"data":\#(data),"eventType":"\#(eventType)","uri":"\#(recorded.event.uri)"}]"#
            guard case .event(let topic, let event) = WAMPCodec.decode(frame) else {
                Issue.record("Ignored a recorded \(recorded.topic) event")
                continue
            }
            #expect(topic.rawValue == recorded.topic)
            #expect(event.uri == recorded.event.uri)
            #expect(event.eventType == recorded.event.eventType)
            #expect(Self.json(event.data) == Self.json(recorded.event.data))
        }
    }

    private static func rawEventType(_ type: LCUEvent.EventType) -> String? {
        switch type {
        case .create: "Create"
        case .update: "Update"
        case .delete: "Delete"
        case .unknown: nil
        }
    }

    private static func json(_ data: Data) -> NSObject? {
        try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? NSObject
    }
}
