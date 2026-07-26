//
//  InstallLocationTests.swift
//  HomeRecTests
//
//  BL-082: bundle-location classification and the two-tier consequence — a hard
//  block for translocation, at most a dismissible note for anything else.
//
//  `classify(_:)` is a pure function of a path, so every branch is covered here
//  with no mocks, no hardware, no permission, and no sleeps. What is *not*
//  covered, and cannot be: real Gatekeeper translocation (needs a quarantined
//  bundle on a mounted disk image), the Finder reveal, and whether a grant
//  actually survives a relaunch. Those are manual, and best run on a non-admin
//  account where the interesting failures live.
//

import Testing
import Foundation
import AppKit
@testable import HomeRec

@MainActor
struct InstallLocationTests {

    // MARK: - classify(_:)

    @Test("Bundle in /Applications classifies as applications")
    func systemApplications() {
        #expect(InstallLocation.classify(URL(fileURLWithPath: "/Applications/Home Rec.app")) == .applications)
    }

    @Test("Bundle in a subfolder of /Applications still classifies as applications")
    func applicationsSubfolder() {
        let url = URL(fileURLWithPath: "/Applications/Utilities/Home Rec.app")
        #expect(InstallLocation.classify(url) == .applications)
    }

    /// `~/Applications` is a deliberate, legitimate choice. It must land in the
    /// soft tier — treating it like translocation is exactly the conflation that
    /// teaches users to ignore the warning that matters.
    @Test("Bundle in ~/Applications classifies as elsewhere, not applications")
    func userApplications() {
        let url = URL(fileURLWithPath: "/Users/someone/Applications/Home Rec.app")
        #expect(InstallLocation.classify(url) == .elsewhere(url))
    }

    @Test("A Gatekeeper AppTranslocation path classifies as translocated")
    func translocatedPath() {
        let url = URL(fileURLWithPath:
            "/private/var/folders/xy/abcdef1234/T/AppTranslocation/"
            + "3F2A1C7E-9B4D-4E1A-8C6F-0D5B2A9E7C31/d/Home Rec.app")
        #expect(InstallLocation.classify(url) == .translocated)
    }

    /// Running straight off the mounted image *without* quarantine (e.g. an image
    /// the user built themselves) is not translocated — it is merely elsewhere.
    /// The block is for the randomised path, not for the volume.
    @Test("Bundle on a mounted volume classifies as elsewhere")
    func mountedVolume() {
        let url = URL(fileURLWithPath: "/Volumes/Home Rec/Home Rec.app")
        #expect(InstallLocation.classify(url) == .elsewhere(url))
    }

    @Test("Bundle in ~/Downloads classifies as elsewhere")
    func downloads() {
        let url = URL(fileURLWithPath: "/Users/someone/Downloads/Home Rec.app")
        #expect(InstallLocation.classify(url) == .elsewhere(url))
    }

    @Test("A DerivedData build classifies as developerBuild")
    func derivedData() {
        let url = URL(fileURLWithPath:
            "/Users/someone/Library/Developer/Xcode/DerivedData/"
            + "HomeRec-abcdefg/Build/Products/Debug/HomeRec.app")
        #expect(InstallLocation.classify(url) == .developerBuild)
    }

    /// `xcodebuild` with a custom `SYMROOT` (CI, scripted builds) produces no
    /// `DerivedData` component — only `Build/Products`.
    @Test("A custom-SYMROOT build directory also classifies as developerBuild")
    func customBuildDirectory() {
        let url = URL(fileURLWithPath: "/tmp/hr-ci/Build/Products/Debug/HomeRec.app")
        #expect(InstallLocation.classify(url) == .developerBuild)
    }

    /// Precedence is fixed deliberately: translocation is the only unrecoverable
    /// state, so a path that somehow looked like both must still block.
    @Test("Translocation wins over a developer-build path match")
    func translocationTakesPrecedence() {
        let url = URL(fileURLWithPath:
            "/private/var/folders/xy/T/AppTranslocation/UUID/d/Build/Products/Debug/HomeRec.app")
        #expect(InstallLocation.classify(url) == .translocated)
    }

    // MARK: - Tiers

    @Test("Only translocation blocks recording")
    func onlyTranslocationBlocks() {
        #expect(InstallLocation.translocated.blocksRecording)
        #expect(InstallLocation.applications.blocksRecording == false)
        #expect(InstallLocation.developerBuild.blocksRecording == false)
        #expect(InstallLocation.elsewhere(URL(fileURLWithPath: "/x/Home Rec.app")).blocksRecording == false)
    }

    @Test("Applications and developer builds have nothing to say")
    func quietTiers() {
        #expect(InstallLocation.applications.explanation == nil)
        #expect(InstallLocation.developerBuild.explanation == nil)
    }

    @Test("The translocation copy names the disk image and the fix, and is not dismissible")
    func translocationCopy() {
        let text = InstallLocation.translocated.explanation
        #expect(text?.contains("disk image") == true)
        #expect(text?.contains("Applications folder") == true)
        #expect(InstallLocation.translocated.noticeIsDismissible == false)
    }

    @Test("The elsewhere note is dismissible")
    func elsewhereIsDismissible() {
        let location = InstallLocation.elsewhere(URL(fileURLWithPath: "/Users/someone/Downloads/Home Rec.app"))
        #expect(location.noticeIsDismissible)
        #expect(location.explanation != nil)
    }

    // MARK: - View-model integration

    /// The presenter override keeps these tests off AppKit: the production path
    /// would order a real panel on screen, which a unit test must not do.
    private func makeViewModel(
        _ location: InstallLocation,
        controller: MockRecordingControlling? = nil,
        onNotice: @escaping () -> Void = {}
    ) -> RecorderViewModel {
        RecorderViewModel(
            controller: controller ?? MockRecordingControlling(),
            permissions: MockPermissionProviding(.granted),
            clock: ManualClock(),
            installLocation: MockInstallLocationProviding(location),
            installNoticePresenter: onNotice
        )
    }

    @Test("A translocated bundle refuses to record and surfaces the explanation")
    func translocationBlocksRecording() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(.translocated, controller: controller)

        await viewModel.startRecording()

        #expect(controller.startCount == 0)
        #expect(viewModel.state == .idle)
        #expect(viewModel.showsInstallLocationNotice)
        #expect(viewModel.installNotice?.contains("disk image") == true)
        #expect(viewModel.installLocationBlocksRecording)
    }

    /// The runtime-ordering requirement: a translocated user must never be sent
    /// into the permission flow. They would follow it correctly and the grant would
    /// still evaporate on relaunch.
    @Test("Translocation pre-empts the permission guide and System Settings")
    func translocationPreemptsPermissionGuide() {
        let permissions = MockPermissionProviding(.denied)
        var noticeCount = 0
        let viewModel = RecorderViewModel(
            controller: MockRecordingControlling(),
            permissions: permissions,
            clock: ManualClock(),
            installLocation: MockInstallLocationProviding(.translocated),
            installNoticePresenter: { noticeCount += 1 }
        )
        // The launch-time notice already fired once; measure from there.
        let baseline = noticeCount

        viewModel.openSystemSettings()

        #expect(noticeCount == baseline + 1)
        #expect(permissions.openSettingsCount == 0)
        #expect(viewModel.permissionGuideIsVisible == false)
    }

    /// Regression guard for a defect found in manual testing of v1.0.1: the
    /// translocation block correctly showed its panel, but the activation observer
    /// still fired the authoritative permission probe — which raises the system
    /// prompt — because permission on a translocated bundle is never `.granted`, so
    /// the BL-085 "skip when granted" guard never tripped. A translocated user was
    /// shown the block *and* pushed into the permission flow at once, the exact harm
    /// BL-082a exists to prevent.
    @Test("Activation never probes permission on a translocated bundle")
    func translocationSuppressesActivationProbe() async {
        let permissions = MockPermissionProviding(.denied)
        let viewModel = RecorderViewModel(
            controller: MockRecordingControlling(),
            permissions: permissions,
            clock: ManualClock(),
            installLocation: MockInstallLocationProviding(.translocated),
            installNoticePresenter: {}
        )
        for _ in 0..<50 { await Task.yield() }
        let baseline = permissions.checkCount

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<50 { await Task.yield() }

        #expect(permissions.checkCount == baseline,
                "A translocated bundle must not run the prompting probe on activation")
        #expect(viewModel.canRecord == false)
    }

    @Test("Dismissing the hard block does not make it go away")
    func hardBlockSurvivesDismissal() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(.translocated, controller: controller)

        viewModel.dismissInstallLocationNotice()
        #expect(viewModel.installNotice != nil)

        await viewModel.startRecording()
        #expect(controller.startCount == 0)
        #expect(viewModel.showsInstallLocationNotice)
    }

    @Test("A bundle in /Applications never warns and records normally")
    func applicationsNeverWarns() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(.applications, controller: controller)

        #expect(viewModel.installNotice == nil)
        #expect(viewModel.showsInstallLocationNotice == false)

        await viewModel.startRecording()
        #expect(viewModel.state == .recording)
        #expect(controller.startCount == 1)
    }

    @Test("A developer build never warns and records normally")
    func developerBuildNeverWarns() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(.developerBuild, controller: controller)

        #expect(viewModel.installNotice == nil)
        #expect(viewModel.showsInstallLocationNotice == false)

        await viewModel.startRecording()
        #expect(viewModel.state == .recording)
        #expect(controller.startCount == 1)
    }

    @Test("A bundle elsewhere notes but never blocks, and the note can be dismissed for good")
    func elsewhereNotesButNeverBlocks() async {
        let controller = MockRecordingControlling()
        let url = URL(fileURLWithPath: "/Users/someone/Applications/Home Rec.app")
        let viewModel = makeViewModel(.elsewhere(url), controller: controller)

        #expect(viewModel.installNotice != nil)
        #expect(viewModel.installLocationBlocksRecording == false)
        // Nothing is presented at launch for the soft tier.
        #expect(viewModel.showsInstallLocationNotice == false)

        await viewModel.startRecording()
        #expect(viewModel.state == .recording)
        #expect(controller.startCount == 1)

        viewModel.dismissInstallLocationNotice()
        #expect(viewModel.installNotice == nil)
    }

    // The positive counterpart — `.elsewhere` still opening System Settings and the
    // permission guide — is deliberately not asserted here: exercising it would
    // materialise the real guide panel and start a live poll loop inside the test
    // process. The behaviour is unchanged from BL-081 and covered by its tests.
}
