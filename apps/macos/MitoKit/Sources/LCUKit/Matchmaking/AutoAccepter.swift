public import MitoCore

public struct AutoAcceptContext: Hashable, Sendable {
    public var settings: GameSettings
    /// The queue of the current matchmaking search, when known.
    public var queue: QueueID?

    public init(settings: GameSettings, queue: QueueID?) {
        self.settings = settings
        self.queue = queue
    }
}

public enum AutoAcceptReport: Equatable, Sendable {
    case accepted
    case skipped(AutoAcceptSkipReason)
    case failed(LCUError)
}

/// Answers ready checks for one connection (`MITO_CONTEXT.md` §11.3).
public struct AutoAccepter: Sendable {
    private let connection: any LCUConnection
    private let clock: any Clock<Duration>

    public init(connection: any LCUConnection, clock: any Clock<Duration> = ContinuousClock()) {
        self.connection = connection
        self.clock = clock
    }

    /// Returns when the connection's events finish and any accept in flight settles, or when
    /// cancelled. `context` is read fresh for each decision, so a settings change applies
    /// mid-delay.
    public func run(
        context: @escaping @Sendable () async -> AutoAcceptContext,
        report: @escaping @Sendable (AutoAcceptReport) async -> Void
    ) async {
        await AutoAcceptSession(
            connection: connection, clock: clock, context: context, report: report
        ).run()
    }
}

private actor AutoAcceptSession {
    private let connection: any LCUConnection
    private let clock: any Clock<Duration>
    private let context: @Sendable () async -> AutoAcceptContext
    private let report: @Sendable (AutoAcceptReport) async -> Void

    // Ready checks carry no id: each run of `InProgress` observations is one generation.
    private var generation = 0
    private var decidedGeneration: Int?
    // The accept waiting out its delay; an observation that rules it out clears it.
    private var waiting: Int?
    private var nextToken = 0

    init(
        connection: any LCUConnection,
        clock: any Clock<Duration>,
        context: @escaping @Sendable () async -> AutoAcceptContext,
        report: @escaping @Sendable (AutoAcceptReport) async -> Void
    ) {
        self.connection = connection
        self.clock = clock
        self.context = context
        self.report = report
    }

    func run() async {
        await withDiscardingTaskGroup { group in
            for await event in connection.events([.readyCheck]) {
                let readyCheck: ReadyCheck?
                do {
                    readyCheck = try ReadyCheck(event)
                } catch {
                    // Unreadable decides nothing; the re-check before accepting covers it.
                    continue
                }
                if let (token, delay) = await observe(readyCheck) {
                    group.addTask { await self.accept(token: token, after: delay) }
                }
            }
        }
    }

    private func observe(_ readyCheck: ReadyCheck?) async -> (token: Int, delay: Duration)? {
        guard let readyCheck else {
            generation += 1
            await withdraw(.readyCheckEnded)
            return nil
        }
        guard readyCheck.state == .inProgress else {
            generation += 1
            await withdraw(.notInProgress(readyCheck.state))
            return nil
        }
        guard readyCheck.playerResponse == .none else {
            decidedGeneration = generation
            await withdraw(.alreadyAnswered(readyCheck.playerResponse))
            return nil
        }
        guard decidedGeneration != generation else { return nil }
        decidedGeneration = generation

        let context = await context()
        switch AutoAcceptPolicy.decide(
            settings: context.settings, queue: context.queue, readyCheck: readyCheck)
        {
        case .skip(let reason):
            await report(.skipped(reason))
            return nil
        case .accept(let delay):
            nextToken += 1
            waiting = nextToken
            return (nextToken, delay)
        }
    }

    private func withdraw(_ reason: AutoAcceptSkipReason) async {
        guard waiting != nil else { return }
        waiting = nil
        await report(.skipped(reason))
    }

    private func accept(token: Int, after delay: Duration) async {
        do {
            try await clock.sleep(for: delay)
        } catch {
            return
        }
        guard waiting == token else { return }

        let current: ReadyCheck
        switch await send(.readyCheck) {
        case .success(let readyCheck):
            current = readyCheck
        case .failure(.http(status: 404, _)):
            return await settle(token, .skipped(.readyCheckEnded))
        case .failure(let error):
            return await settle(token, .failed(error))
        }
        guard waiting == token else { return }

        let context = await context()
        guard waiting == token else { return }
        if case .skip(let reason) = AutoAcceptPolicy.decide(
            settings: context.settings, queue: context.queue, readyCheck: current)
        {
            return await settle(token, .skipped(reason))
        }

        guard !Task.isCancelled else { return }
        // Committed: from here on nothing withdraws this accept.
        waiting = nil
        switch await send(.acceptReadyCheck) {
        case .success: await report(.accepted)
        case .failure(let error): await report(.failed(error))
        }
    }

    private func settle(_ token: Int, _ outcome: AutoAcceptReport) async {
        guard waiting == token else { return }
        waiting = nil
        await report(outcome)
    }

    private func send<R>(_ endpoint: LCUEndpoint<R>) async -> Result<R, LCUError> {
        do {
            return .success(try await connection.send(endpoint))
        } catch {
            return .failure(error)
        }
    }
}
