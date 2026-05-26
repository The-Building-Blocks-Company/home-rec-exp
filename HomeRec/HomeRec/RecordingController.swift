//
//  RecordingController.swift
//  HomeRec
//
//  Orchestrates the recording workflow
//

import Foundation
import os

/// Controller that coordinates audio recording workflow
class RecordingController: RecordingControlling {

    // MARK: - Properties

    private let captureManager: AudioCapturing
    private let audioRecorder: AudioFileWriting

    private var currentRecordingURL: URL?

    /// Callback for waveform visualization data
    var onWaveformData: (([Float]) -> Void)?

    // MARK: - Initialization

    init(
        captureManager: AudioCapturing? = nil,
        audioRecorder: AudioFileWriting? = nil
    ) {
        self.captureManager = captureManager ?? ScreenCaptureAudioManager()
        self.audioRecorder = audioRecorder ?? AudioRecorder()
    }

    // MARK: - Public Methods

    /// Start recording system audio
    /// - Returns: URL where the recording is being saved
    /// - Throws: Error if recording cannot start
    @MainActor
    func startRecording() async throws -> URL {
        // Generate file path
        let fileURL = generateFilePath()

        // Wire waveform callback
        audioRecorder.onWaveformData = onWaveformData

        // Start audio recorder first (creates WAV file)
        try audioRecorder.startRecording(to: fileURL)

        // Set up capture with audio callback
        let recorder = audioRecorder  // Keep strong reference
        try await captureManager.setupCapture { sampleBuffer in
            recorder.processAudioSample(sampleBuffer)
        }

        // Start capturing system audio
        try await captureManager.startCapture()

        currentRecordingURL = fileURL
        Log.recorder.info("Recording started")
        return fileURL
    }

    /// Stop recording
    /// - Throws: Error if stop fails
    func stopRecording() async throws {
        // Stop capturing audio
        try await captureManager.stopCapture()

        // Stop recorder and finalize WAV file
        try audioRecorder.stopRecording()

        // Clean up capture manager
        await captureManager.cleanup()

        audioRecorder.onWaveformData = nil
        currentRecordingURL = nil
        Log.recorder.info("Recording stopped")
    }

    /// Check if currently recording
    var isRecording: Bool {
        return captureManager.capturing
    }

    /// Get current recording URL
    var recordingURL: URL? {
        return currentRecordingURL
    }

    // MARK: - Private Methods

    /// Generate file path with timestamp
    /// - Returns: URL for the new recording file
    private func generateFilePath() -> URL {
        // Get Desktop directory
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!

        // Generate filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "recording_\(timestamp).wav"

        return desktopURL.appendingPathComponent(filename)
    }

    // MARK: - Cleanup

    deinit {
        // Capture managers directly to avoid referencing self inside the Task closure
        let captureManager = captureManager
        let audioRecorder = audioRecorder
        Task { @MainActor in
            guard captureManager.capturing else { return }
            try? await captureManager.stopCapture()
            try? audioRecorder.stopRecording()
            await captureManager.cleanup()
        }
    }
}
