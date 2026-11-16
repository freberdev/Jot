import Foundation

/// Runs an action once things have been quiet for a while.
@MainActor
public protocol Debouncing: AnyObject {
    /// Schedules `action`, replacing any action that is still waiting.
    func schedule(_ action: @escaping @MainActor () -> Void)
    /// Drops the waiting action, if any.
    func cancel()
}

@MainActor
public final class TimerDebouncer: Debouncing {
    private let delay: Duration
    private var task: Task<Void, Never>?

    public init(delay: Duration = .milliseconds(500)) {
        self.delay = delay
    }

    public func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
