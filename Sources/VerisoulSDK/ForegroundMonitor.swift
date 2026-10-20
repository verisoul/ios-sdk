import Foundation
import UIKit

/// Tracks whether the host app is in the foreground.
///
/// The SDK collects data only while the app is in the foreground. iOS can launch an app in the
/// background (silent push, background fetch, location) and suspend it a few seconds later, so
/// collection is held until the app comes to the foreground, and `session()` timeouts count only
/// foreground time.
///
/// `willResignActive` (Control Center, calls, system alerts) still counts as foreground; only
/// `didEnterBackground` counts as background.
///
/// Lock order: `Verisoul.sessionLock` before `lock`. The edge callback runs without `lock` held,
/// so callers that hold `sessionLock` must not trigger a state change.
final class ForegroundMonitor {

    static let shared = ForegroundMonitor()

    private let lock = NSLock()
    private var installed = false
    private var pinned = false
    private var foreground = false
    private var stateSeq = 0
    private var accruedForegroundTime: TimeInterval = 0
    private var foregroundStintStart: TimeInterval?
    private var epoch = 0
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var onForegroundEdge: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    private func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    var isForeground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return foreground
    }

    /// Bumped each time the app goes from the foreground to the background.
    var backgroundEpoch: Int {
        lock.lock()
        defer { lock.unlock() }
        return epoch
    }

    /// Total time the app has spent in the foreground, for timeouts that pause in the background.
    func foregroundTime() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return accruedForegroundTime + (foregroundStintStart.map { now() - $0 } ?? 0)
    }

    /// Called once by Verisoul; runs on each background-to-foreground transition.
    func setOnForegroundEdge(_ callback: @escaping () -> Void) {
        lock.lock()
        onForegroundEdge = callback
        lock.unlock()
    }

    /// Installs the lifecycle observers once and reads the current state.
    /// Callers must not hold `Verisoul.sessionLock`: on the main thread the initial read can run
    /// the edge callback, which takes that lock.
    func installIfNeeded() {
        lock.lock()
        if installed {
            lock.unlock()
            return
        }
        installed = true
        let seqAtInstall = stateSeq
        lock.unlock()

        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        for name in [UIApplication.willEnterForegroundNotification,
                     UIApplication.didBecomeActiveNotification,
                     UIScene.willEnterForegroundNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.setForeground(true)
            })
        }
        tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setForeground(false)
        })
        lock.lock()
        observers = tokens
        lock.unlock()

        // applicationState must be read on the main thread. Off the main thread (for example a
        // React Native module queue) read it asynchronously; never block on the main thread here.
        let readInitialState: () -> Void = { [weak self] in
            self?.setForeground(UIApplication.shared.applicationState != .background, ifSeq: seqAtInstall)
        }
        if Thread.isMainThread {
            readInitialState()
        } else {
            DispatchQueue.main.async { readInitialState() }
        }
    }

    /// Records a state change. `ifSeq` drops a stale initial read that lost a race with a
    /// notification. `fromTest` pins the state so real notifications are ignored.
    func setForeground(_ value: Bool, ifSeq: Int? = nil, fromTest: Bool = false) {
        lock.lock()
        if (pinned && !fromTest) || (ifSeq != nil && ifSeq != stateSeq) {
            lock.unlock()
            return
        }
        if fromTest { pinned = true }
        stateSeq += 1
        let wasForeground = foreground
        foreground = value

        var ready: [CheckedContinuation<Void, Error>] = []
        if value && !wasForeground {
            foregroundStintStart = now()
            ready = Array(waiters.values)
            waiters.removeAll()
        } else if !value && wasForeground {
            accruedForegroundTime += now() - (foregroundStintStart ?? now())
            foregroundStintStart = nil
            epoch += 1
        }
        let callback = onForegroundEdge
        lock.unlock()

        guard value && !wasForeground else { return }
        UnifiedLogger.shared.info("App entered the foreground", className: String(describing: ForegroundMonitor.self))
        // Start deferred work before waking waiters so they find it
        callback?()
        ready.forEach { $0.resume() }
    }

    /// Returns once the app is in the foreground. Throws `CancellationError` if the calling task
    /// is cancelled while waiting.
    func waitUntilForeground() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if foreground {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[id] = continuation
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let continuation = waiters.removeValue(forKey: id)
            lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }
    }

    // MARK: - Test hooks

    var _waiterCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    var _stateSeq: Int {
        lock.lock()
        defer { lock.unlock() }
        return stateSeq
    }

    /// Pins the state (ignoring real notifications), clears the clock and epoch, and releases
    /// waiters with `CancellationError`. Runs no edge callback.
    func _resetForTesting(foreground value: Bool) {
        lock.lock()
        pinned = true
        stateSeq += 1
        foreground = value
        accruedForegroundTime = 0
        foregroundStintStart = value ? now() : nil
        epoch = 0
        let released = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()
        released.forEach { $0.resume(throwing: CancellationError()) }
    }
}
