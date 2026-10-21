import Foundation

/// WAMP 1.0 framing as the League client speaks it (`MITO_CONTEXT.md` §10.5).
enum WAMPCodec {
    enum Inbound: Equatable, Sendable {
        case event(LCUTopic, LCUEvent)
        /// Anything else: other opcodes, topics Mito never subscribes to, malformed frames.
        case ignored
    }

    private enum Opcode {
        static let subscribe = 5
        static let unsubscribe = 6
        static let event = 8
    }

    static func subscribe(_ topic: LCUTopic) -> String {
        frame(Opcode.subscribe, topic)
    }

    static func unsubscribe(_ topic: LCUTopic) -> String {
        frame(Opcode.unsubscribe, topic)
    }

    static func decode(_ frame: String) -> Inbound {
        guard
            let message = try? JSONSerialization.jsonObject(
                with: Data(frame.utf8), options: .fragmentsAllowed) as? [Any],
            message.count >= 3,
            let opcode = message[0] as? Int, opcode == Opcode.event,
            let name = message[1] as? String, let topic = LCUTopic(rawValue: name),
            let payload = message[2] as? [String: Any],
            let uri = payload["uri"] as? String,
            let eventType = payload["eventType"] as? String,
            let data = try? JSONSerialization.data(
                withJSONObject: payload["data"] ?? NSNull(),
                options: [.fragmentsAllowed, .withoutEscapingSlashes])
        else { return .ignored }
        return .event(topic, LCUEvent(uri: uri, eventType: .init(eventType), data: data))
    }

    // Topic names are fixed ASCII constants, so interpolation needs no JSON escaping.
    private static func frame(_ opcode: Int, _ topic: LCUTopic) -> String {
        #"[\#(opcode),"\#(topic.rawValue)"]"#
    }
}
