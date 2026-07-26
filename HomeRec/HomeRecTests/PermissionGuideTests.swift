//
//  PermissionGuideTests.swift
//  HomeRecTests
//
//  BL-081: the permission guide's state machine, poll-loop lifetime, and the
//  overlapping-probe race.
//
//  Panel window behaviour (staying visible while System Settings is frontmost,
//  not stealing focus) is deliberately absent — it is AppKit behaviour with no
//  test seam, and was verified manually against the real bundled app instead.
//  See private/reports/2026-07-26-bl081-panel-surface-spike.md.
//

import Testing
import Foundation
@testable import HomeRec

@MainActor
struct PermissionGuideTests {

    private func makeModel(_ permissions: MockPermissionProviding) -> PermissionGuideModel {
        PermissionGuideModel(permissions: permissions, clock: ImmediatePollClock(), interval: 0)
    }

    // MARK: - Copy

    /// The navigation copy is the whole feature — if it stops naming the section
    /// that actually holds Home Rec, the guide sends people somewhere useless.
    @Test("Navigation hint names the real section and disambiguates the confusable one")
    func navigationHintNamesBothSections() {
        let hint = PermissionKind.screenCapture.navigationHint
        #expect(hint.contains("Screen & System Audio Recording"))
        #expect(hint.contains("System Audio Recording Only"))
    }

    @Test("Section names come from PermissionKind, not from view code")
    func sectionNamesLiveInOnePlace() {
        #expect(PermissionKind.screenCapture.settingsSectionName == "Screen & System Audio Recording")
        #expect(PermissionKind.screenCapture.confusableSectionName == "System Audio Recording Only")
    }

    @Test("Deep-link anchor is the screen-capture pane")
    func anchorIsScreenCapture() {
        #expect(PermissionKind.screenCapture.settingsAnchor == "Privacy_ScreenCapture")
    }

    // MARK: - Grant detection

    @Test("Model starts out awaiting the grant")
    func startsAwaiting() {
        let model = makeModel(MockPermissionProviding(.denied))
        #expect(model.state == .awaitingGrant)
    }

    @Test("A probe that finds permission granted flips state and fires onGranted once")
    func grantDetected() async {
        let permissions = MockPermissionProviding(.denied)
        let model = makeModel(permissions)
        var grantedCallbacks = 0
        model.onGranted = { grantedCallbacks += 1 }

        await model.probeOnce()
        #expect(model.state == .awaitingGrant)
        #expect(grantedCallbacks == 0)

        permissions.status = .granted
        await model.probeOnce()
        #expect(model.state == .granted)
        #expect(grantedCallbacks == 1)

        // A late probe must not re-announce a grant the app already acted on.
        await model.probeOnce()
        #expect(grantedCallbacks == 1)
    }

    @Test("The probe asks about the model's own permission kind")
    func probesTheRightKind() async {
        let permissions = MockPermissionProviding(.denied)
        await makeModel(permissions).probeOnce()
        #expect(permissions.requestedKinds == [.screenCapture])
    }

    // MARK: - Poll-loop lifetime

    /// The leaked-loop guard. State alone can't show this: a model that reached
    /// `.granted` looks identical whether or not it is still probing forever.
    @Test("Polling stops once permission is granted")
    func pollingStopsOnGrant() async {
        let permissions = MockPermissionProviding(.granted)
        let model = makeModel(permissions)

        model.startPolling()
        for _ in 0..<2000 where model.state != .granted { await Task.yield() }

        let settled = permissions.checkCount
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == settled)
    }

    @Test("Polling stops when the guide is dismissed while still denied")
    func pollingStopsOnDismiss() async {
        let permissions = MockPermissionProviding(.denied)
        let model = makeModel(permissions)

        model.startPolling()
        for _ in 0..<2000 where permissions.checkCount < 3 { await Task.yield() }
        model.stopPolling()

        // Let the cancellation land, then confirm probing has actually ceased.
        for _ in 0..<20 { await Task.yield() }
        let settled = permissions.checkCount
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == settled)
    }

    @Test("Starting twice does not run two loops")
    func startIsIdempotent() async {
        let permissions = MockPermissionProviding(.denied)
        let model = makeModel(permissions)

        model.startPolling()
        model.startPolling()
        for _ in 0..<2000 where permissions.checkCount < 5 { await Task.yield() }
        model.stopPolling()
        for _ in 0..<20 { await Task.yield() }

        // Two loops would roughly double the probes between two observations;
        // sampling twice and comparing growth is enough to catch that.
        let first = permissions.checkCount
        for _ in 0..<20 { await Task.yield() }
        #expect(permissions.checkCount == first)
    }

    @Test("Releasing the model cancels its poll loop")
    func deinitCancelsPolling() async {
        let permissions = MockPermissionProviding(.denied)
        do {
            let model = makeModel(permissions)
            model.startPolling()
            for _ in 0..<2000 where permissions.checkCount < 2 { await Task.yield() }
        }
        for _ in 0..<20 { await Task.yield() }
        let settled = permissions.checkCount
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == settled)
    }

    // MARK: - The poll budget (BL-085)

    /// An abandoned panel used to probe `SCShareableContent` once a second for the
    /// life of the process. It now gives up — and says so, because a panel that
    /// silently stopped working would strand someone who grants a minute late.
    @Test("Polling gives up after its budget and reports it")
    func pollingTimesOut() async {
        let permissions = MockPermissionProviding(.denied)
        let model = PermissionGuideModel(
            permissions: permissions,
            clock: ImmediatePollClock(),
            interval: 0,
            maxProbes: 5
        )

        model.startPolling()
        for _ in 0..<2000 where model.state != .timedOut { await Task.yield() }

        #expect(permissions.checkCount == 5)
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == 5, "Timing out must actually stop the loop")
    }

    @Test("Check again resumes polling and can still detect the grant")
    func resumeAfterTimeout() async {
        let permissions = MockPermissionProviding(.denied)
        let model = PermissionGuideModel(
            permissions: permissions,
            clock: ImmediatePollClock(),
            interval: 0,
            maxProbes: 3
        )

        model.startPolling()
        for _ in 0..<2000 where model.state != .timedOut { await Task.yield() }

        permissions.status = .granted
        model.resumePolling()
        for _ in 0..<2000 where model.state != .granted { await Task.yield() }
        #expect(model.state == .granted)
    }

    @Test("Resume does nothing unless the loop actually timed out")
    func resumeIsInertWhileWaiting() async {
        let permissions = MockPermissionProviding(.denied)
        let model = PermissionGuideModel(
            permissions: permissions,
            clock: ImmediatePollClock(),
            interval: 0,
            maxProbes: 100
        )
        model.resumePolling()
        for _ in 0..<20 { await Task.yield() }
        #expect(permissions.checkCount == 0)
        #expect(model.state == .awaitingGrant)
    }

    // MARK: - The overlapping-probe race

    /// The failure this guards is the one the whole feature exists to prevent:
    /// the user grants permission, and the app still insists it is missing
    /// because a slower in-flight probe wrote a stale `.denied` afterwards.
    @Test("A slow stale probe cannot overwrite a fresh granted result")
    func staleProbeCannotOverwriteGrant() async {
        let permissions = MockPermissionProviding(.denied)
        permissions.holdsChecks = true
        let viewModel = RecorderViewModel(
            controller: MockRecordingControlling(),
            permissions: permissions,
            clock: ManualClock(),
            notificationCenter: NotificationCenter()
        )

        // First probe is in flight and suspended, holding `.denied`.
        let first = Task { await viewModel.checkPermission() }
        for _ in 0..<2000 where permissions.checkCount < 1 { await Task.yield() }

        // Permission is granted, and a second caller asks — the situation the
        // activation observer and the poll loop create between them.
        permissions.status = .granted
        let second = Task { await viewModel.checkPermission() }
        for _ in 0..<10 { await Task.yield() }

        permissions.holdsChecks = false
        permissions.resumePendingChecks()
        _ = await first.value
        _ = await second.value

        #expect(viewModel.permissionStatus == .granted)
    }

    @Test("Overlapping callers share one probe rather than each issuing their own")
    func overlappingCallersSingleFlight() async {
        let permissions = MockPermissionProviding(.denied)
        permissions.holdsChecks = true
        let viewModel = RecorderViewModel(
            controller: MockRecordingControlling(),
            permissions: permissions,
            clock: ManualClock(),
            notificationCenter: NotificationCenter()
        )
        // Launch no longer probes at all — it reads state silently (BL-085) — so
        // there is no in-flight probe to piggyback on and the count starts at zero.
        // (This test used to wait for an init probe that no longer happens; it kept
        // passing only because a *real* app activation reached the shared
        // NotificationCenter mid-suite and fired one. With the center injected,
        // that accident is gone and the assertion has to stand on its own.)
        #expect(permissions.checkCount == 0)

        let a = Task { await viewModel.checkPermission() }
        let b = Task { await viewModel.checkPermission() }
        for _ in 0..<50 { await Task.yield() }

        permissions.holdsChecks = false
        permissions.resumePendingChecks()
        _ = await a.value
        _ = await b.value

        // Two callers, one probe: the second joined the first rather than issuing
        // its own. Without the single-flight this would be 2.
        #expect(permissions.checkCount == 1)
    }
}
