//
//  PermissionGrantWatcher.swift
//  HomeRec
//
//  Watches for a permission grant made in System Settings while the app is
//  running (BL-088). This is the retry mechanism the guide panel used to bundle
//  with its UI: a single probe on returning to the app can race the TCC write —
//  observed live, 2026-07-28: grant via the Settings toggle with no poll running
//  left the app stuck at "Almost ready" until relaunch, while the identical flow
//  with a poll caught the grant within a second. The UI was redundant; this loop
//  is not.
//
//  BL-085-compliant for the same reason the panel's loop was: it only ever
//  starts behind the user's own click ("Open System Settings" / Record).
//

import Foundation

@MainActor
final class PermissionGrantWatcher {

    /// Probes issued since this watcher was created. Exposed so tests can assert
    /// the loop actually *stops* — a leaked poll task is invisible otherwise.
    private(set) var probeCount = 0

    /// Whether the loop is currently running — the BL-085 guard's test seam.
    var isPolling: Bool { pollTask != nil }

    let kind: PermissionKind

    private let permissions: PermissionProviding
    private let clock: PollClock
    private let interval: TimeInterval
    /// Probes allowed per run. A count rather than a deadline so the bound is
    /// exact under an injected clock. On exhaustion the loop simply stops — the
    /// activation re-probe and the Open System Settings button both remain as
    /// natural retries, so no "gave up" UI is needed.
    private let maxProbes: Int
    private var probesThisRun = 0
    private var pollTask: Task<Void, Never>?
    private var granted = false

    /// Called exactly once, when the grant is first observed.
    var onGranted: (() -> Void)?

    init(
        kind: PermissionKind = .screenCapture,
        permissions: PermissionProviding,
        clock: PollClock? = nil,
        interval: TimeInterval = 1.0,
        maxProbes: Int = 600   // ~10 minutes at the default 1 s interval
    ) {
        self.kind = kind
        self.permissions = permissions
        self.clock = clock ?? SystemPollClock()
        self.interval = interval
        self.maxProbes = maxProbes
    }

    deinit {
        // `deinit` is nonisolated; cancelling is safe from any context and is the
        // only teardown that matters — an orphaned loop would keep probing
        // `SCShareableContent` for the life of the process.
        pollTask?.cancel()
    }

    /// Begin watching. Idempotent — a second click must not start a second loop.
    ///
    /// The loop deliberately does **not** hold `self` across the wait: retaining
    /// the watcher for the loop's lifetime would make `deinit` unreachable and the
    /// loop immortal. Each iteration re-acquires `self` weakly, does one step, and
    /// drops it before sleeping.
    func startPolling() {
        guard pollTask == nil, !granted else { return }
        probesThisRun = 0
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let step = await self?.pollStep() else { return }
                guard case .wait(let clock, let interval) = step else { return }
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return   // cancelled while waiting
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private enum PollStep {
        case wait(PollClock, TimeInterval)
        case finished
    }

    private func pollStep() async -> PollStep {
        await probeOnce()
        if granted { return .finished }
        probesThisRun += 1
        if probesThisRun >= maxProbes {
            stopPolling()
            return .finished
        }
        return .wait(clock, interval)
    }

    /// One probe. Separated from the loop so the transition is testable without
    /// task scheduling.
    func probeOnce() async {
        probeCount += 1
        let status = await permissions.checkPermission(kind)
        guard status == .granted, !granted else { return }
        granted = true
        stopPolling()
        onGranted?()
    }
}
