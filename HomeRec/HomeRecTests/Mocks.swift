//
//  Mocks.swift
//  HomeRecTests
//
//  Test doubles for the recording protocols, enabling hardware-free tests
//  of the workflow (BL-003 seams used by BL-020 / BL-005).
//

import Foundation
import CoreMedia
@testable import HomeRec

@MainActor
final class MockAudioCapturing: AudioCapturing {
    var capturing = false
    var onStreamError: (@MainActor (String) -> Void)?
    private(set) var setupCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cleanupCount = 0
    private var audioCallback: ((CMSampleBuffer) -> Void)?

    func setupCapture(audioCallback: @escaping (CMSampleBuffer) -> Void) async throws {
        setupCount += 1
        self.audioCallback = audioCallback
    }

    func startCapture() async throws {
        startCount += 1
        capturing = true
    }

    func stopCapture() async throws {
        stopCount += 1
        capturing = false
    }

    func cleanup() async {
        cleanupCount += 1
    }

    /// Simulate the capture stream dying unexpectedly.
    func simulateStreamError(_ message: String) {
        capturing = false
        onStreamError?(message)
    }
}

@MainActor
final class MockAudioFileWriting: AudioFileWriting {
    var onWaveformData: (([Float]) -> Void)?
    private(set) var recording = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// Fired each time `stopRecording()` (the finalize point) is called.
    var onStop: (() -> Void)?

    func startRecording(to fileURL: URL) throws {
        startCount += 1
        recording = true
    }

    func processAudioSample(_ sampleBuffer: CMSampleBuffer) {}

    func stopRecording() throws {
        stopCount += 1
        recording = false
        onStop?()
    }
}

@MainActor
final class MockPermissionProviding: PermissionProviding {
    var status: PermissionStatus

    init(_ status: PermissionStatus = .granted) {
        self.status = status
    }

    func checkPermission() async -> PermissionStatus { status }
    func requestPermission() async -> Bool { status == .granted }
    func openSystemPreferences() {}
}

@MainActor
final class ManualClock: DurationClock {
    var now: Date = Date(timeIntervalSinceReferenceDate: 0)

    func startTicking(every interval: TimeInterval, onTick: @escaping @MainActor () -> Void) {}
    func stopTicking() {}
}
