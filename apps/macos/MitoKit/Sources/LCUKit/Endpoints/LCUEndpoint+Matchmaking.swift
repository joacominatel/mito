extension LCUEndpoint where Response == ReadyCheck {
    /// 404 when there is no ready check.
    public static var readyCheck: Self {
        Self(method: .get, path: "/lol-matchmaking/v1/ready-check")
    }
}

extension LCUEndpoint where Response == LCUNoContent {
    public static var acceptReadyCheck: Self {
        Self(method: .post, path: "/lol-matchmaking/v1/ready-check/accept")
    }
}
