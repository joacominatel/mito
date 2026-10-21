extension LCUEndpoint where Response == ChampSelectSession {
    /// 404 outside champ select.
    public static var champSelectSession: Self {
        Self(method: .get, path: "/lol-champ-select/v1/session")
    }
}
