//
//  AudioCapturing.swift
//  HomeRec
//
//  Abstraction over the system-audio capture source so the recording
//  workflow can be exercised with a mock instead of real hardware.
//

import Foundation
import CoreMedia

/// A source of captured system audio. Implemented by `ScreenCaptureAudioManager`.
@MainActor
protocol AudioCapturing: AnyObject, Sendable {
    var capturing: Bool { get }
    /// Called when the capture stream stops unexpectedly (e.g. permission revoked,
    /// display sleep, another capturer). The argument is a plain-language detail.
    var onStreamError: (@MainActor (String) -> Void)? { get set }
    func setupCapture(audioCallback: @escaping (CMSampleBuffer) -> Void) async throws
    func startCapture() async throws
    func stopCapture() async throws
    func cleanup() async
}
