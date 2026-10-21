extension LCUEndpoint where Response == GameflowPhase {
    /// The body is a bare JSON string, e.g. `"ChampSelect"`.
    public static var gameflowPhase: Self {
        Self(method: .get, path: "/lol-gameflow/v1/gameflow-phase")
    }
}
