import Observation

/// Calls `apply` with `read()` now and again each time the observable state it reads changes to
/// a different value, until the calling task is cancelled. For reactions no view can own, since
/// the app may run with no window and no menu bar icon.
func observeChanges<Value: Equatable>(
    of read: @escaping () -> Value, apply: (Value) -> Void
) async {
    var last: Value?
    while !Task.isCancelled {
        let (changed, signal) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let value = withObservationTracking(read) { signal.yield() }
        if value != last {
            last = value
            apply(value)
        }
        for await _ in changed { break }
    }
}
