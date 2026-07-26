//
//  PermissionProbeTests.swift
//  HomeRecTests
//
//  BL-085: which permission API each call site uses, and why it matters.
//
//  The distinction under test is invisible in the UI — both APIs return the same
//  status — so nothing but these tests will notice if a future change points a
//  launch path at the authoritative probe again. That probe can raise a system
//  prompt, so the regression it guards is "a permission dialog appears at launch
//  before the user has asked for anything".
//

import Testing
import Foundation
import AppKit
@testable import HomeRec

@MainActor
struct PermissionProbeTests {

    private func makeViewModel(_ permissions: MockPermissionProviding) -> RecorderViewModel {
        RecorderViewModel(
            controller: MockRecordingControlling(),
            permissions: permissions,
            clock: ManualClock()
        )
    }

    // MARK: - Launch

    /// The core of the item. A launch probe through `checkPermission` is what put
    /// an unrequested dialog on screen; preflight is silent.
    @Test("Launch reads permission silently and never uses the prompting probe")
    func launchUsesPreflightOnly() async {
        let permissions = MockPermissionProviding(.denied)
        let viewModel = makeViewModel(permissions)

        // Give any stray Task spawned during init a chance to run.
        for _ in 0..<50 { await Task.yield() }

        #expect(permissions.preflightCount == 1)
        #expect(permissions.checkCount == 0, "Launch must not call the probe that can prompt")
        #expect(viewModel.permissionStatus == .denied)
    }

    @Test("A granted launch is reflected without the prompting probe")
    func grantedLaunchUsesPreflight() async {
        let permissions = MockPermissionProviding(.granted)
        let viewModel = makeViewModel(permissions)
        for _ in 0..<50 { await Task.yield() }

        #expect(viewModel.permissionStatus == .granted)
        #expect(permissions.checkCount == 0)
    }

    // MARK: - The guide's poll loop

    /// Guards the inverse mistake: "optimising" the loop onto the silent API.
    /// The real `CGPreflightScreenCaptureAccess` latches its answer at process
    /// start — measured holding `.granted` for 57s after permission was revoked —
    /// so a loop built on it would wait forever for a grant it can never see.
    /// The mock reproduces that by pinning `preflightStatus` while `status` moves.
    @Test("The guide polls the live API, not the latched one")
    func guidePollsTheLiveAPI() async {
        let permissions = MockPermissionProviding(.denied)
        permissions.preflightStatus = .denied     // frozen, as the real API is
        let model = PermissionGuideModel(
            permissions: permissions,
            clock: ImmediatePollClock(),
            interval: 0
        )

        model.startPolling()
        while permissions.checkCount < 3 { await Task.yield() }

        // The system grants; preflight stays stale forever.
        permissions.status = .granted
        while model.state != .granted { await Task.yield() }

        #expect(model.state == .granted, "A latched preflight would never reach this")
        #expect(permissions.preflightCount == 0, "The loop must not use the silent API")
    }

    // MARK: - Activation re-probe

    @Test("Activation does not re-probe when permission is already granted")
    func activationSkipsProbeWhenGranted() async {
        let permissions = MockPermissionProviding(.granted)
        let viewModel = makeViewModel(permissions)
        for _ in 0..<50 { await Task.yield() }
        let baseline = permissions.checkCount

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<50 { await Task.yield() }

        #expect(viewModel.permissionStatus == .granted)
        #expect(permissions.checkCount == baseline, "Already granted — nothing to ask")
    }

    /// BL-040 regression guard. Skipping the probe when granted must not become
    /// skipping it when it is the only thing that can notice a grant.
    @Test("Activation still re-detects a grant made while the app was running")
    func activationReprobesWhenNotGranted() async {
        let permissions = MockPermissionProviding(.denied)
        let viewModel = makeViewModel(permissions)
        for _ in 0..<50 { await Task.yield() }
        #expect(viewModel.permissionStatus == .denied)

        permissions.status = .granted
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        while viewModel.permissionStatus != .granted { await Task.yield() }

        #expect(viewModel.permissionStatus == .granted)
        #expect(permissions.checkCount >= 1)
    }
}
