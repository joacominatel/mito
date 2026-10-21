/// Credentials from a `LeagueClientUx` command line as `ps` prints it (`MITO_CONTEXT.md` §10.1 A).
enum ProcessArguments {
    static func credentials(fromCommandLine line: String) -> LCUCredentials? {
        let words = words(in: line)
        guard let firstOption = words.firstIndex(where: { $0.hasPrefix("--") }),
            words[..<firstOption].joined(separator: " ").contains("LeagueClientUx"),
            let port = value(of: "app-port", in: words).flatMap(LCUDiscovery.port),
            let token = value(of: "remote-auth-token", in: words), !token.isEmpty
        else { return nil }
        return LCUCredentials(port: port, token: token)
    }

    /// `--key=value` or `--key value`; the exact key, so `--riotclient-app-port` never matches.
    private static func value(of key: String, in words: [String]) -> String? {
        for (index, word) in words.enumerated() {
            if word.hasPrefix("--\(key)=") {
                return String(word.dropFirst(key.count + 3))
            }
            if word == "--\(key)", index + 1 < words.count, !words[index + 1].hasPrefix("--") {
                return words[index + 1]
            }
        }
        return nil
    }

    /// Splits on whitespace outside quotes and drops the quotes.
    private static func words(in line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
