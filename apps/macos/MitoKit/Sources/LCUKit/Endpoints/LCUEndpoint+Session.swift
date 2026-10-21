extension LCUEndpoint where Response == CurrentSummoner {
    /// 404 while the client is still loading (§10.2), so callers retry.
    public static var currentSummoner: Self {
        Self(method: .get, path: "/lol-summoner/v1/current-summoner")
    }
}
