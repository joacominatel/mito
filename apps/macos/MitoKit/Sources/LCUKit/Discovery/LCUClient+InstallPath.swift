extension LCUClient {
    /// Reads `installPath()` on every discovery attempt; `nil` means the default install
    /// (§10.1). Lives here because it only changes how discovery finds the lockfile.
    public init(installPath: @escaping @Sendable () async -> String?) {
        self.init(discovery: LCUDiscovery(installPath: installPath))
    }
}
