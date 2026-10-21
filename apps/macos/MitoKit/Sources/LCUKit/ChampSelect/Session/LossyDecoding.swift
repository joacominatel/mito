/// The elements of a JSON array that decode as `Element`; the rest are skipped.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not advance the container, so step over the element.
                _ = try container.decode(Skipped.self)
            }
        }
        self.elements = elements
    }

    private struct Skipped: Decodable {
        init(from decoder: any Decoder) {}
    }
}

extension KeyedDecodingContainer {
    /// Missing, `null`, or not an array decodes as `[]`.
    func decodeLossyArray<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element] {
        (try? decodeIfPresent(LossyArray<Element>.self, forKey: key))?.elements ?? []
    }

    /// The LCU sends `0` for "none", and `-1` for a skipped ban.
    func decodeID<ID: RawRepresentable>(_ type: ID.Type, forKey key: Key) throws -> ID?
    where ID.RawValue == Int {
        guard let rawValue = try decodeIfPresent(Int.self, forKey: key), rawValue > 0 else {
            return nil
        }
        return ID(rawValue: rawValue)
    }
}
