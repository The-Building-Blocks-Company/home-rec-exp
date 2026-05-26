//
//  RecordingControlling.swift
//  HomeRec
//
//  Abstraction over the recording workflow orchestrator so the view model
//  can be driven by a mock controller in tests.
//

import Foundation

/// Orchestrates the start/stop recording workflow. Implemented by `RecordingController`.
@MainActor
protocol RecordingControlling: AnyObject {
    var onWaveformData: (([Float]) -> Void)? { get set }
    /// Called when the underlying capture stream fails unexpectedly mid-recording.
    var onStreamError: (@MainActor (String) -> Void)? { get set }
    var isRecording: Bool { get }
    var recordingURL: URL? { get }
    func startRecording() async throws -> URL
    func stopRecording() async throws
    /// Finalize after an unexpected capture failure: best-effort capture teardown
    /// plus finalizing the partial recording so captured audio is preserved.
    func finalizeAfterFailure() async
}
