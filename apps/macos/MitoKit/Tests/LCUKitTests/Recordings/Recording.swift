import Foundation
import LCUKit
import MitoTestSupport

/// A recorded `fixtures/lcu/<scenario>/` directory (format v0), read in place.
struct Recording {
    static let scenarios = ["ready-check", "champ-select", "lobby-to-game"]

    struct Exchange {
        let path: String
        let status: Int
        let body: Data
    }

    struct Event {
        let topic: String
        let event: LCUEvent
    }

    let clientPatch: String
    let queueID: Int
    let rest: [Exchange]
    let events: [Event]

    init(_ scenario: String) throws {
        let directory = Fixtures.url("lcu/\(scenario)")
        let meta = try Self.object(Data(contentsOf: directory.appending(path: "scenario.json")))
        guard let patch = meta["clientPatch"] as? String, let queue = meta["queueId"] as? Int
        else { throw Malformed() }
        clientPatch = patch
        queueID = queue
        rest = try Self.lines(directory.appending(path: "rest.jsonl")).map { line in
            guard let path = line["path"] as? String, let status = line["status"] as? Int else {
                throw Malformed()
            }
            return Exchange(
                path: Self.restored(path), status: status, body: try Self.json(line["body"]))
        }
        events = try Self.lines(directory.appending(path: "events.jsonl")).map { line in
            guard let topic = line["topic"] as? String, let uri = line["uri"] as? String,
                let eventType = line["eventType"] as? String
            else { throw Malformed() }
            return Event(
                topic: Self.restored(topic),
                event: LCUEvent(
                    uri: Self.restored(uri), eventType: .init(eventType),
                    data: try Self.json(line["data"])))
        }
    }

    func exchanges(at path: String) -> [Exchange] {
        rest.filter { $0.path == path }
    }

    /// The bodies of the successful responses, in recording order.
    func bodies(at path: String) -> [Data] {
        exchanges(at: path).filter { $0.status == 200 }.map(\.body)
    }

    func events(on topic: LCUTopic) -> [LCUEvent] {
        events.filter { $0.topic == topic.rawValue }.map(\.event)
    }

    struct Malformed: Error {}

    // lcu-recorder 0.1.0 anonymized the champ-select chat domain, which is the plugin's own name,
    // in every path and topic too. Undo it here until the scenarios are re-recorded.
    private static func restored(_ text: String) -> String {
        text.replacing("/anon-14/", with: "/lol-champ-select/")
            .replacing("OnJsonApiEvent_anon-14_", with: "OnJsonApiEvent_lol-champ-select_")
    }

    private static func lines(_ url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try object(Data($0.utf8))
        }
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Malformed()
        }
        return object
    }

    private static func json(_ value: Any?) throws -> Data {
        try JSONSerialization.data(withJSONObject: value ?? NSNull(), options: .fragmentsAllowed)
    }
}
