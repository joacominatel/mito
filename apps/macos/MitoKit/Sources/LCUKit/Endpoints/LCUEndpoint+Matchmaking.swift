extension LCUEndpoint where Response == ReadyCheck {
    /// 404 outside matchmaking; `Invalid` while searching and after the ready check ends.
    public static var readyCheck: Self {
        Self(method: .get, path: "/lol-matchmaking/v1/ready-check")
    }
}

extension LCUEndpoint where Response == LCUNoContent {
    public static var acceptReadyCheck: Self {
        Self(method: .post, path: "/lol-matchmaking/v1/ready-check/accept")
    }
}
