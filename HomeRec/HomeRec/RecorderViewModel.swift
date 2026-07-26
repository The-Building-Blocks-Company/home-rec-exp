//
//  RecorderViewModel.swift
//  HomeRec
//
//  View model for the recorder UI
//

import Foundation
import SwiftUI
import AppKit
import Combine
import os

/// View model managing recording state and user interactions
@MainActor
class RecorderViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Single source of truth for the recording lifecycle. The UI derives from this.
    @Published private(set) var state: RecordingState = .idle
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var showError = false
    /// A recovery action to offer alongside the current error, if any.
    @Published var recoverySuggestion: RecoverySuggestion?
    /// Set once a recording passes the long-recording threshold.
    @Published var showLongRecordingWarning = false
    /// Whether the first-run onboarding sheet should be shown.
    @Published var showOnboarding = false
    @Published var lastRecordingURL: URL?
    @Published var permissionStatus: PermissionStatus = .notDetermined
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 200)
    /// Display name of the current save location (folder name, or "Desktop").
    @Published private(set) var saveLocationName: String = "Desktop"
    /// Whether a non-default save location is configured (controls the Reset affordance).
    @Published private(set) var hasCustomSaveLocation = false

    /// The output format for new recordings (BL-015). Captured at record start —
    /// it can't change mid-recording (the shelf is hidden then). Persisted across
    /// launches; mutate only via `setFormat(_:)`.
    @Published private(set) var selectedFormat: AudioFormat = .wav

    /// Where this bundle is running from (BL-082). Fixed for the process' lifetime —
    /// the bundle cannot move out from under a running app.
    let installLocation: InstallLocation

    /// Whether the install-location explanation is currently on screen.
    @Published private(set) var showsInstallLocationNotice = false

    /// Set once the user dismisses a *soft* note. Has no effect on the hard block.
    @Published private(set) var installNoticeDismissed = false

    /// Whether a recording is actively capturing. Derived from `state`.
    var isRecording: Bool { state == .recording }

    /// Whether the app is actually in a position to record: permission granted and
    /// the bundle in a location where that grant will survive. The record button is
    /// live only in this state; otherwise it carries a corrective action instead.
    var canRecord: Bool { permissionStatus == .granted && !installLocation.blocksRecording }

    /// Recording is refused outright only for a translocated bundle: the grant it
    /// needs cannot survive, so "it worked once and then stopped" is the *best*
    /// case if we let it through. Merely living outside `/Applications` never
    /// blocks — that is a legitimate choice TCC handles fine, and conflating the
    /// two trains users to dismiss the warning that matters.
    var installLocationBlocksRecording: Bool { installLocation.blocksRecording }

    /// The note to show about the install location, or `nil` when there is nothing
    /// worth saying. A soft note disappears once dismissed; the hard block does
    /// not, because dismissing it would leave the app quietly unable to hold a grant.
    var installNotice: String? {
        guard let text = installLocation.explanation else { return nil }
        if installLocation.noticeIsDismissible && installNoticeDismissed { return nil }
        return text
    }

    /// Full path of the current save location, for tooltips / accessibility.
    var saveLocationPath: String { saveLocation.resolvedDirectory.path }

    // MARK: - Private Properties

    private let controller: RecordingControlling
    private let permissions: PermissionProviding
    private let clock: DurationClock
    private let saveLocation: SaveLocationProviding
    private var recordingStartTime: Date?
    private var longRecordingWarned = false
    private var activationObserver: NSObjectProtocol?
    /// Whether the launch activation has already been observed and swallowed.
    private var hasSeenLaunchActivation = false
    /// In-flight permission probe, so overlapping callers share one result
    /// rather than racing to write `permissionStatus`. See `checkPermission()`.
    private var permissionProbe: Task<PermissionStatus, Never>?
    /// The guide panel, created on first use — a menu-bar app may never have
    /// shown a window, so it can't be owned by one.
    private var guidePanel: PermissionGuidePanel?
    private let installLocationProvider: InstallLocationProviding
    /// The install-location panel, created on first use for the same reason.
    private var installNoticePanel: FloatingPanelHost?
    /// Overrides how the install-location notice is presented.
    ///
    /// Exists for tests: the default presenter materialises a real `NSPanel` and
    /// orders it on screen, which a unit test asserting "translocation blocks
    /// recording" has no business doing. Production never passes this.
    private let installNoticePresenter: (() -> Void)?
    /// Visible main windows, reported by the windows themselves.
    ///
    /// Deliberately *not* inferred from `NSApp.windows`: at init no window exists
    /// yet, and a menu-bar app owns a visible `NSStatusBarWindow` for the whole
    /// process — so "any visible non-panel window" answers `false` exactly when a
    /// window is about to appear, and `true` forever after even with every real
    /// window closed. Both answers are wrong at the moment they matter.
    private(set) var visibleWindowCount = 0
    private var launchNoticeObserver: NSObjectProtocol?
    /// Injected so tests get their own activation notifications. `.default` is
    /// process-global, and the suites are unserialized: one suite's synthetic
    /// `didBecomeActive` would otherwise reach every other suite's live view
    /// model, which is both a false pass and a false failure waiting to happen.
    private let notificationCenter: NotificationCenter
    private let defaults: UserDefaults
    private let onboardingCompletedKey = "hasCompletedOnboarding"
    private let selectedFormatKey = "selectedFormat"

    // MARK: - Initialization

    init(
        controller: RecordingControlling? = nil,
        permissions: PermissionProviding? = nil,
        clock: DurationClock? = nil,
        saveLocation: SaveLocationProviding? = nil,
        installLocation: InstallLocationProviding? = nil,
        defaults: UserDefaults = .standard,
        installNoticePresenter: (() -> Void)? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.notificationCenter = notificationCenter
        let resolvedInstallLocation = installLocation ?? BundleInstallLocation()
        self.installLocationProvider = resolvedInstallLocation
        self.installLocation = resolvedInstallLocation.location
        self.installNoticePresenter = installNoticePresenter
        let resolvedSaveLocation = saveLocation ?? SaveLocationManager(defaults: defaults)
        self.saveLocation = resolvedSaveLocation
        self.controller = controller ?? RecordingController(saveLocation: resolvedSaveLocation)
        self.permissions = permissions ?? PermissionManager()
        self.clock = clock ?? SystemDurationClock()
        self.defaults = defaults
        self.showOnboarding = !defaults.bool(forKey: onboardingCompletedKey)
        self.selectedFormat = Self.loadFormat(from: defaults, key: selectedFormatKey)
        self.controller.onStreamError = { [weak self] message in
            self?.handleStreamFailure(message)
        }
        refreshSaveLocationDisplay()
        // Re-probe permission whenever the app regains focus, so granting Screen
        // Recording in System Settings takes effect without a relaunch (BL-040).
        //
        // Skipped once permission is granted — which is every activation for every
        // already-set-up user. That probe is an XPC round-trip that can also raise
        // the system prompt, and re-asking a question already answered "yes" buys
        // nothing. A revocation mid-session surfaces when recording next starts.
        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // The first didBecomeActive is launch itself, not the user
                // returning from anywhere — probing there raises the system prompt
                // on a fresh install with zero clicks, the exact BL-085 violation.
                // BL-040's scenario (grant in Settings, come back) is always a
                // *later* activation, so skipping the first loses nothing.
                if !self.hasSeenLaunchActivation {
                    self.hasSeenLaunchActivation = true
                    return
                }
                guard self.permissionStatus != .granted else { return }
                // A translocated bundle must never be walked into the permission
                // flow (BL-082a): the authoritative probe raises the system prompt,
                // and any grant it wins evaporates on next launch. The block
                // surfaces are the only correct response.
                guard !self.installLocation.blocksRecording else { return }
                await self.checkPermission()
            }
        }
        // Launch uses the *silent* read (BL-085). The authoritative probe can raise
        // the system prompt, and firing it here throws a permission dialog at
        // someone who has not asked for anything yet — the app wanting to know its
        // own state is not a good enough reason to interrupt. Preflight is accurate
        // at launch, which is exactly and only what is needed here.
        permissionStatus = self.permissions.preflight()
        // A translocated bundle is broken from the first launch, so the block state
        // is set now — but nothing is *presented* from here. At this point the view
        // model is still being constructed as a `@StateObject`, so no window exists
        // yet; presenting here would always take the no-window branch and put the
        // panel up moments before the main window appears saying the same thing.
        // The window announces itself via `mainWindowDidAppear()`; a launch that
        // opens no window at all is covered by the fallback below.
        if self.installLocation.blocksRecording {
            self.showsInstallLocationNotice = true
            launchNoticeObserver = notificationCenter.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.visibleWindowCount == 0 else { return }
                    self.showInstallLocationNotice()
                }
            }
        }
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
        if let launchNoticeObserver {
            notificationCenter.removeObserver(launchNoticeObserver)
        }
    }

    // MARK: - Public Methods

    /// Check permission status.
    ///
    /// Single-flighted: `didBecomeActiveNotification` and the permission guide's
    /// poll loop can both ask at once, and `SCShareableContent` is an XPC round-trip
    /// whose latency varies. Without this, two probes overlap and the *slower* one
    /// writes last — so a stale `.denied` can land after a fresh `.granted` and the
    /// UI insists permission is missing seconds after the user granted it. That is
    /// precisely the failure the guide exists to prevent, so it must not be
    /// reintroduced by the guide's own polling.
    func checkPermission() async {
        if let inFlight = permissionProbe {
            _ = await inFlight.value
            return
        }
        let probe = Task { await permissions.checkPermission() }
        permissionProbe = probe
        let status = await probe.value
        permissionProbe = nil
        permissionStatus = status
    }

    /// Request permission
    func requestPermission() async {
        let granted = await permissions.requestPermission()
        permissionStatus = granted ? .granted : .denied

        if !granted {
            presentError(
                "Home Rec needs Screen Recording permission to capture audio (it never records your screen). You can turn it on in System Settings.",
                recovery: .openSettings
            )
        }
    }

    /// Start recording
    func startRecording() async {
        // Only legal from idle or a prior error state.
        guard state.canTransition(to: .starting) else { return }

        // Install location is checked *before* permission (BL-082). A translocated
        // bundle can be granted permission and will still lose it on the next
        // launch, so sending the user into the permission flow here would hand them
        // advice that is worse than useless — they'd follow it correctly and the
        // grant would evaporate anyway.
        guard !installLocation.blocksRecording else {
            showInstallLocationNotice()
            return
        }

        // Check permission first; if not granted, remain in the current state.
        if permissionStatus != .granted {
            await requestPermission()
            if permissionStatus != .granted {
                return
            }
        }

        transition(to: .starting)

        do {
            // Wire waveform callback
            controller.onWaveformData = { [weak self] samples in
                Task { @MainActor in
                    self?.waveformSamples = samples
                }
            }
            // Start recording in the selected format (captured here, at start).
            let fileURL = try await controller.startRecording(format: selectedFormat)
            lastRecordingURL = fileURL
            recordingStartTime = clock.now
            duration = 0
            longRecordingWarned = false

            transition(to: .recording)

            // Start duration timer
            startTimer()

            // If the chosen save folder was unavailable, the recording fell back to
            // the Desktop — tell the user (non-blocking; recording continues).
            if saveLocation.isConfiguredLocationUnavailable {
                presentError(RecorderError.saveLocationUnavailable.message, recovery: .chooseFolder)
            }

        } catch RecordingControllerError.insufficientDiskSpace {
            Log.recorder.error("Refusing to record: insufficient disk space")
            transition(to: .error(.diskFull))
        } catch {
            Log.recorder.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            transition(to: .error(.startFailed(error.localizedDescription)))
        }
    }

    /// Stop recording
    func stopRecording() async {
        guard state.canTransition(to: .stopping) else { return }

        transition(to: .stopping)

        do {
            try await controller.stopRecording()

            stopTimer()
            waveformSamples = Array(repeating: 0, count: 200)

            transition(to: .idle)

        } catch {
            Log.recorder.error("Failed to stop recording: \(error.localizedDescription, privacy: .public)")
            transition(to: .error(.stopFailed(error.localizedDescription)))
        }
    }

    /// Toggle recording state
    func toggleRecording() async {
        switch state {
        case .idle, .error:
            await startRecording()
        case .recording:
            await stopRecording()
        case .starting, .stopping, .recovering:
            // Ignore taps during in-flight transitions.
            break
        }
    }

    /// Reveal recording in Finder
    func revealInFinder() {
        guard let url = lastRecordingURL else { return }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Open System Settings *and* leave a guide on screen (BL-081).
    ///
    /// Opening the pane alone is where this flow used to end, and it abandoned the
    /// user at the hardest moment: macOS offers no way to scroll to or highlight an
    /// app's row, the system prompt never fires twice, and Home Rec's own copy
    /// ("only captures audio") points people at the one section it isn't listed in.
    /// The panel outlives the focus change and says where to look; the poll loop
    /// notices the grant without the user having to come back and check.
    /// Runtime ordering (BL-082): the install-location check runs *before* the
    /// permission guide, and replaces it entirely when the bundle is translocated.
    /// Telling a translocated user to flip a toggle is actively harmful — they will
    /// do it correctly, the grant will still evaporate on relaunch, and they will
    /// now believe the app simply doesn't work. So neither the guide nor System
    /// Settings is opened in that case.
    func openSystemSettings() {
        guard !installLocation.blocksRecording else {
            showInstallLocationNotice()
            return
        }
        showPermissionGuide()
        permissions.openSystemPreferences()
    }

    // MARK: - Install location (BL-082)

    /// A main window appeared and will render the block itself.
    func mainWindowDidAppear() {
        visibleWindowCount += 1
        // The window is the canonical surface. Anything the panel was saying, it
        // now says — and saying one fact twice at once reads as two faults.
        installNoticePanel?.dismiss()
    }

    /// A main window went away. If that was the last one and the app is blocked,
    /// nothing on screen carries the block any more — which for a menu-bar app
    /// means a silently dead app. That is the panel's remaining job.
    func mainWindowDidDisappear() {
        visibleWindowCount = max(0, visibleWindowCount - 1)
        if installLocation.blocksRecording && visibleWindowCount == 0 {
            showInstallLocationNotice()
        }
    }

    /// Show the install-location explanation.
    ///
    /// The floating panel is a **fallback, not the primary surface**: the main
    /// window and the menu-bar popover both carry the block inline, so the panel
    /// appears only when no window exists to say it — a translocated launch
    /// running as a pure menu-bar presence, where silence would mean a dead app
    /// with no explanation.
    func showInstallLocationNotice() {
        guard let message = installNotice else { return }
        showsInstallLocationNotice = true

        // The window check comes first, ahead of the test seam, so the seam models
        // *panel presentation* rather than "this method was called" — otherwise a
        // test can't tell the suppressed case from the presented one.
        if visibleWindowCount > 0 {
            // A window is already showing this; `orderOut` deliberately leaves
            // `showsInstallLocationNotice` true — the block state persists, only
            // the duplicate surface goes away. (`orderOut` does not fire
            // `windowWillClose`, so `onWillClose` won't clear it either.)
            installNoticePanel?.dismiss()
            return
        }

        if let installNoticePresenter {
            installNoticePresenter()
            return
        }

        if installNoticePanel == nil {
            let panel = FloatingPanelHost(title: "Home Rec", width: 340) { [weak self] in
                AnyView(
                    InstallLocationNoticeView(
                        message: message,
                        onReveal: { self?.revealAppInFinder() },
                        onDismiss: { self?.dismissInstallLocationNotice() }
                    )
                )
            }
            panel.onWillClose = { [weak self] in self?.showsInstallLocationNotice = false }
            installNoticePanel = panel
        }
        installNoticePanel?.show()
    }

    /// Dismiss the notice. A soft note stays dismissed; the hard block will come
    /// back the next time recording is attempted, because nothing has been fixed.
    func dismissInstallLocationNotice() {
        showsInstallLocationNotice = false
        if installLocation.noticeIsDismissible {
            installNoticeDismissed = true
        }
        installNoticePanel?.dismiss()
    }

    /// Reveal the app bundle itself in Finder. The translocated path is randomised
    /// and unguessable, so this is the only practical way for the user to get hold
    /// of the bundle they've been asked to drag.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([installLocationProvider.bundleURL])
    }

    /// Whether the guide panel is currently on screen.
    var permissionGuideIsVisible: Bool { guidePanel?.isVisible ?? false }

    /// Show the guide panel, creating it on first use.
    func showPermissionGuide() {
        if guidePanel == nil {
            let model = PermissionGuideModel(permissions: permissions)
            model.onGranted = { [weak self] in
                // Mirror the grant into the app's own state so every surface
                // updates, not just the panel.
                Task { @MainActor in await self?.checkPermission() }
            }
            guidePanel = PermissionGuidePanel(model: model) { [weak self] in
                guard let self else { return }
                self.permissions.openSystemPreferences()
            }
        }
        guidePanel?.show()
    }

    /// Present the folder chooser; persist the picked directory.
    func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveLocation.resolvedDirectory
        panel.prompt = "Choose"
        panel.message = "Choose where Home Rec saves recordings"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            saveLocation.setSaveDirectory(url)
            refreshSaveLocationDisplay()
        }
    }

    /// Reset the save location back to the Desktop default.
    func resetSaveLocation() {
        saveLocation.reset()
        refreshSaveLocationDisplay()
    }

    /// Select the output format for new recordings and persist the choice (BL-015).
    /// No-ops for a format that isn't currently available (defensive — the picker
    /// only offers `AudioFormat.available`).
    func setFormat(_ format: AudioFormat) {
        guard AudioFormat.available.contains(format) else { return }
        selectedFormat = format
        defaults.set(format.rawValue, forKey: selectedFormatKey)
    }

    /// Mark first-run onboarding complete and dismiss it.
    func completeOnboarding() {
        defaults.set(true, forKey: onboardingCompletedKey)
        showOnboarding = false
    }

    /// Re-open the onboarding sheet (e.g. from the Help menu).
    func showOnboardingAgain() {
        showOnboarding = true
    }

    // MARK: - Private Methods

    /// Handle an unexpected capture-stream failure mid-recording: surface the
    /// error state immediately, then finalize the partial recording so the
    /// audio captured before the failure is preserved.
    private func handleStreamFailure(_ message: String) {
        guard state == .recording else { return }
        stopTimer()
        waveformSamples = Array(repeating: 0, count: 200)
        transition(to: .error(.streamFailed(message)))
        Task { [weak self] in
            await self?.controller.finalizeAfterFailure()
        }
    }

    /// Apply a state transition, rejecting illegal ones. Surfaces the alert when
    /// entering an error state.
    private func transition(to next: RecordingState) {
        guard state.canTransition(to: next) else {
            Log.recorder.error("Rejected illegal recording-state transition")
            return
        }
        state = next
        if case .error(let recorderError) = next {
            presentError(recorderError.message, recovery: recorderError.recovery)
        }
    }

    /// Start duration timer
    private func startTimer() {
        clock.startTicking(every: 0.1) { [weak self] in
            guard let self, let startTime = self.recordingStartTime else { return }
            self.duration = self.clock.now.timeIntervalSince(startTime)
            if !self.longRecordingWarned && self.duration >= DiskSpace.longRecordingThreshold {
                self.longRecordingWarned = true
                self.showLongRecordingWarning = true
            }
        }
    }

    /// Stop duration timer
    private func stopTimer() {
        clock.stopTicking()
    }

    /// Present a user-facing error with optional recovery action.
    private func presentError(_ message: String, recovery: RecoverySuggestion?) {
        errorMessage = message
        recoverySuggestion = recovery
        showError = true
    }

    /// Perform the current error's recovery action (from the alert button).
    func performRecovery() {
        let suggestion = recoverySuggestion
        showError = false
        switch suggestion {
        case .openSettings:
            openSystemSettings()
        case .tryAgain:
            Task { await startRecording() }
        case .chooseFolder:
            chooseSaveLocation()
        case nil:
            break
        }
    }

    /// Refresh the published save-location display from the provider.
    private func refreshSaveLocationDisplay() {
        saveLocationName = saveLocation.configuredDirectory?.lastPathComponent ?? "Desktop"
        hasCustomSaveLocation = saveLocation.configuredDirectory != nil
    }

    /// Read the persisted format, falling back to `.wav` when the stored value is
    /// absent, unparseable, or no longer available (e.g. a format was removed, or
    /// a future build wrote one this build doesn't support). Pure function of its
    /// inputs so it's safe to call during `init`.
    private static func loadFormat(from defaults: UserDefaults, key: String) -> AudioFormat {
        guard
            let raw = defaults.string(forKey: key),
            let format = AudioFormat(rawValue: raw),
            AudioFormat.available.contains(format)
        else {
            return .wav
        }
        return format
    }

    // MARK: - Computed Properties

    /// Formatted duration string (MM:SS)
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Status text
    var statusText: String {
        switch state {
        case .recording:
            return "Recording"
        case .starting:
            return "Starting…"
        case .stopping:
            return "Stopping…"
        case .recovering:
            return "Recovering…"
        case .error:
            return "Something went wrong"
        case .idle:
            // A translocated bundle can't hold a permission grant, so "Almost
            // ready / grant permission" would be a lie — point at the real fix.
            if installLocation.blocksRecording { return "Move to Applications" }
            return permissionStatus != .granted ? "Almost ready" : "Play something, then hit record"
        }
    }
}
