//
//  PermissionGrantWatcherTests.swift
//  HomeRecTests
//
//  BL-088: the grant watcher's loop lifetime and budget, plus the view-model
//  probe races it inherits from BL-081. The watcher is the retry mechanism that
//  used to live behind the guide panel: a single probe on returning to the app
//  can race the TCC write, and without the loop a missed race strands the app
//  at "Almost ready" until relaunch — observed live, 2026-07-28.
//
//  The permission *copy* tests survive from BL-081 — the navigation hint is
//  still the feature, it just lives only in the main window and popover now.
//

import Testing
import Foundation
@testable import HomeRec

@MainActor
struct PermissionGrantWatcherTests {

    private func makeWatcher(
        _ permissions: MockPermissionProviding,
        maxProbes: Int = 600
    ) -> PermissionGrantWatcher {
        PermissionGrantWatcher(
            permissions: permissions,
            clock: ImmediatePollClock(),
            interval: 0,
            maxProbes: maxProbes
        )
    }

    // MARK: - Copy (BL-081's surviving fix)

    /// The navigation copy is the whole feature — if it stops naming the section
    /// that actually holds Home Rec, the app sends people somewhere useless.
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

    @Test("A probe that finds permission granted fires onGranted exactly once")
    func grantDetectedOnce() async {
        let permissions = MockPermissionProviding(.denied)
        let watcher = makeWatcher(permissions)
        var grantedCallbacks = 0
        watcher.onGranted = { grantedCallbacks += 1 }

        await watcher.probeOnce()
        #expect(grantedCallbacks == 0)

        permissions.status = .granted
        await watcher.probeOnce()
        #expect(grantedCallbacks == 1)

        // A late probe must not re-announce a grant the app already acted on.
        await watcher.probeOnce()
        #expect(grantedCallbacks == 1)
    }

    // MARK: - Loop lifetime

    /// The leaked-loop guard: a watcher that reached the grant looks identical
    /// from outside whether or not it is still probing forever.
    @Test("Polling stops once permission is granted")
    func pollingStopsOnGrant() async {
        let permissions = MockPermissionProviding(.granted)
        let watcher = makeWatcher(permissions)

        watcher.startPolling()
        for _ in 0..<2000 where watcher.isPolling { await Task.yield() }

        let settled = permissions.checkCount
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == settled)
    }

    @Test("Polling stops when told to, while still denied")
    func pollingStopsOnDemand() async {
        let permissions = MockPermissionProviding(.denied)
        let watcher = makeWatcher(permissions)

        watcher.startPolling()
        for _ in 0..<2000 where permissions.checkCount < 3 { await Task.yield() }
        watcher.stopPolling()

        for _ in 0..<20 { await Task.yield() }
        let settled = permissions.checkCount
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == settled)
    }

    @Test("Starting twice does not run two loops")
    func startIsIdempotent() async {
        let permissions = MockPermissionProviding(.denied)
        let watcher = makeWatcher(permissions)

        watcher.startPolling()
        watcher.startPolling()
        for _ in 0..<2000 where permissions.checkCount < 5 { await Task.yield() }
        watcher.stopPolling()
        for _ in 0..<20 { await Task.yield() }

        let first = permissions.checkCount
        for _ in 0..<20 { await Task.yield() }
        #expect(permissions.checkCount == first)
    }

    @Test("Releasing the watcher cancels its poll loop")
    func deinitCancelsPolling() async {
        let permissions = MockPermissionProviding(.denied)
        do {
            let watcher = makeWatcher(permissions)
            watcher.startPolling()
            for _ in 0..<2000 where permissions.checkCount < 2 { await Task.yield() }
        }
        for _ in 0..<20 { await Task.yield() }
        let settled = permissions.checkCount
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == settled)
    }

    /// On budget exhaustion the loop just stops — no "gave up" UI. The activation
    /// re-probe and the Open System Settings button remain as natural retries.
    @Test("Polling stops at its budget")
    func pollingStopsAtBudget() async {
        let permissions = MockPermissionProviding(.denied)
        let watcher = makeWatcher(permissions, maxProbes: 5)

        watcher.startPolling()
        for _ in 0..<2000 where watcher.isPolling { await Task.yield() }

        #expect(permissions.checkCount == 5)
        for _ in 0..<50 { await Task.yield() }
        #expect(permissions.checkCount == 5, "Exhausting the budget must actually stop the loop")
    }

    // MARK: - The overlapping-probe race (view model, unchanged from BL-081)

    /// The failure the single-flight prevents: the user grants, and a slower
    /// in-flight probe writes a stale `.denied` afterwards.
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

        let first = Task { await viewModel.checkPermission() }
        for _ in 0..<2000 where permissions.checkCount < 1 { await Task.yield() }

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
        #expect(permissions.checkCount == 0)

        let a = Task { await viewModel.checkPermission() }
        let b = Task { await viewModel.checkPermission() }
        for _ in 0..<50 { await Task.yield() }

        permissions.holdsChecks = false
        permissions.resumePendingChecks()
        _ = await a.value
        _ = await b.value

        #expect(permissions.checkCount == 1)
    }
}
