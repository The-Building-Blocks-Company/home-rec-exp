//
//  PermissionGuideModel.swift
//  HomeRec
//
//  State behind the permission guide panel (BL-081): what to tell the user, and
//  noticing the moment they grant so the app can say so without being refocused.
//

import Foundation
import Combine

@MainActor
final class PermissionGuideModel: ObservableObject {

    enum State: Equatable {
        case awaitingGrant
        case granted
    }

    @Published private(set) var state: State = .awaitingGrant

    /// Probes issued since this model was created. Exposed so tests can assert the
    /// loop actually *stops* — a leaked poll task is invisible from state alone.
    private(set) var probeCount = 0

    let kind: PermissionKind

    private let permissions: PermissionProviding
    private let clock: PollClock
    private let interval: TimeInterval
    private var pollTask: Task<Void, Never>?

    /// Called once when permission is observed as granted.
    var onGranted: (() -> Void)?

    var navigationHint: String { kind.navigationHint }

    init(
        kind: PermissionKind = .screenCapture,
        permissions: PermissionProviding,
        clock: PollClock? = nil,
        interval: TimeInterval = 1.0
    ) {
        self.kind = kind
        self.permissions = permissions
        self.clock = clock ?? SystemPollClock()
        self.interval = interval
    }

    deinit {
        // `deinit` is nonisolated; cancelling is safe from any context and is the
        // only teardown that matters — an orphaned loop would keep probing
        // `SCShareableContent` for the life of the process.
        pollTask?.cancel()
    }

    // MARK: - Polling

    /// Begin watching for the grant. Idempotent: calling twice does not start a
    /// second loop, which matters because the panel can be re-shown.
    ///
    /// The loop deliberately does **not** hold `self` across the wait. Calling a
    /// method on the model for the whole loop would retain it for the loop's
    /// lifetime — which makes the model un-deallocatable while polling, so the
    /// `deinit` that is supposed to stop the loop can never run and the loop
    /// becomes immortal. Instead each iteration re-acquires `self` weakly, does
    /// one step, and drops it before sleeping; once the model goes away the next
    /// iteration finds `nil` and exits on its own.
    func startPolling() {
        guard pollTask == nil else { return }
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

    /// Stop watching. Called on dismiss, on window close, and on grant.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private enum PollStep {
        case wait(PollClock, TimeInterval)
        case finished
    }

    /// One iteration's worth of work, returning what the loop should do next.
    /// Split out so the strong reference to `self` ends when this returns.
    private func pollStep() async -> PollStep {
        await probeOnce()
        return state == .granted ? .finished : .wait(clock, interval)
    }

    /// One probe. Separated from the loop so the state transition can be tested
    /// without involving task scheduling at all.
    func probeOnce() async {
        probeCount += 1
        let status = await permissions.checkPermission(kind)
        guard status == .granted else { return }
        guard state != .granted else { return }   // fire `onGranted` exactly once
        state = .granted
        stopPolling()
        onGranted?()
    }
}
