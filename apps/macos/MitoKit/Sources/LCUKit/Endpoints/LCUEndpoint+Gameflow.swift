extension LCUEndpoint where Response == GameflowPhase {
    /// The body is a bare JSON string, e.g. `"ChampSelect"`.
    public static var gameflowPhase: Self {
        Self(method: .get, path: "/lol-gameflow/v1/gameflow-phase")
    }
}

extension LCUEndpoint where Response == GameflowSession {
    public static var gameflowSession: Self {
        Self(method: .get, path: "/lol-gameflow/v1/session")
    }
}
