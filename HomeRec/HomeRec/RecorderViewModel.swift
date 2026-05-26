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

    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var lastRecordingURL: URL?
    @Published var permissionStatus: PermissionStatus = .notDetermined
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 200)

    // MARK: - Private Properties

    private let controller = RecordingController()
    private var recordingStartTime: Date?
    private var timer: Timer?

    // MARK: - Initialization

    init() {
        Task {
            await checkPermission()
        }
    }

    // MARK: - Public Methods

    /// Check permission status
    func checkPermission() async {
        permissionStatus = await PermissionManager.checkPermission()
    }

    /// Request permission
    func requestPermission() async {
        let granted = await PermissionManager.requestPermission()
        permissionStatus = granted ? .granted : .denied

        if !granted {
            showError(message: "Screen Recording permission is required to record system audio. Please grant permission in System Settings.")
        }
    }

    /// Start recording
    func startRecording() async {
        // Check permission first
        if permissionStatus != .granted {
            await requestPermission()
            if permissionStatus != .granted {
                return
            }
        }

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

            // Update state
            isRecording = true
            recordingStartTime = Date()
            duration = 0

            // Start duration timer
            startTimer()

        } catch {
            Log.recorder.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            showError(message: "Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stop recording
    func stopRecording() async {
        do {
            // Stop recording
            try await controller.stopRecording()

            // Update state
            isRecording = false
            stopTimer()
            waveformSamples = Array(repeating: 0, count: 200)

        } catch {
            Log.recorder.error("Failed to stop recording: \(error.localizedDescription, privacy: .public)")
            showError(message: "Failed to stop recording: \(error.localizedDescription)")
        }
    }

    /// Toggle recording state
    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    /// Reveal recording in Finder
    func revealInFinder() {
        guard let url = lastRecordingURL else { return }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Open System Settings
    func openSystemSettings() {
        PermissionManager.openSystemPreferences()
    }

    // MARK: - Private Methods

    /// Start duration timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let startTime = self.recordingStartTime else { return }
                self.duration = Date().timeIntervalSince(startTime)
            }
        }
    }

    /// Stop duration timer
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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
        if isRecording {
            return "Recording"
        } else if permissionStatus != .granted {
            return "Almost ready"
        } else {
            return "Play something, then hit record"
        }
    }

    // MARK: - Cleanup

    deinit {
        timer?.invalidate()
        timer = nil
    }
}
