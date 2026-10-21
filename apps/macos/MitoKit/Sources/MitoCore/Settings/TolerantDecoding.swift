extension KeyedDecodingContainer {
    /// A missing, null, or undecodable value falls back to `fallback`, so one bad field never
    /// resets the rest of the settings.
    func decode<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
