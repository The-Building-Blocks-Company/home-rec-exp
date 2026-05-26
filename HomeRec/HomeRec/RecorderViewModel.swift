//
//  RecorderViewModel.swift
//  HomeRec
//
//  View model for the recorder UI
//

import Foundation
import SwiftUI
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
    @Published var lastRecordingURL: URL?
    @Published var permissionStatus: PermissionStatus = .notDetermined
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 200)

    /// Whether a recording is actively capturing. Derived from `state`.
    var isRecording: Bool { state == .recording }

    // MARK: - Private Properties

    private let controller: RecordingControlling
    private let permissions: PermissionProviding
    private let clock: DurationClock
    private var recordingStartTime: Date?

    // MARK: - Initialization

    init(
        controller: RecordingControlling? = nil,
        permissions: PermissionProviding? = nil,
        clock: DurationClock? = nil
    ) {
        self.controller = controller ?? RecordingController()
        self.permissions = permissions ?? PermissionManager()
        self.clock = clock ?? SystemDurationClock()
        Task {
            await checkPermission()
        }
    }

    // MARK: - Public Methods

    /// Check permission status
    func checkPermission() async {
        permissionStatus = await permissions.checkPermission()
    }

    /// Request permission
    func requestPermission() async {
        let granted = await permissions.requestPermission()
        permissionStatus = granted ? .granted : .denied

        if !granted {
            showError(message: "Screen Recording permission is required to record system audio. Please grant permission in System Settings.")
        }
    }

    /// Start recording
    func startRecording() async {
        // Only legal from idle or a prior error state.
        guard state.canTransition(to: .starting) else { return }

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
            // Start recording
            let fileURL = try await controller.startRecording()
            lastRecordingURL = fileURL
            recordingStartTime = clock.now
            duration = 0

            transition(to: .recording)

            // Start duration timer
            startTimer()

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

    /// Open System Settings
    func openSystemSettings() {
        permissions.openSystemPreferences()
    }

    // MARK: - Private Methods

    /// Apply a state transition, rejecting illegal ones. Surfaces the alert when
    /// entering an error state.
    private func transition(to next: RecordingState) {
        guard state.canTransition(to: next) else {
            Log.recorder.error("Rejected illegal recording-state transition")
            return
        }
        state = next
        if case .error(let recorderError) = next {
            showError(message: recorderError.message)
        }
    }

    /// Start duration timer
    private func startTimer() {
        clock.startTicking(every: 0.1) { [weak self] in
            guard let self, let startTime = self.recordingStartTime else { return }
            self.duration = self.clock.now.timeIntervalSince(startTime)
        }
    }

    /// Stop duration timer
    private func stopTimer() {
        clock.stopTicking()
    }

    /// Show error message
    private func showError(message: String) {
        errorMessage = message
        showError = true
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
            return permissionStatus != .granted ? "Almost ready" : "Play something, then hit record"
        }
    }
}
