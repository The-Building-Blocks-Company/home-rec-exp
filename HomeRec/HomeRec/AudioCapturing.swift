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
    func setupCapture(audioCallback: @escaping (CMSampleBuffer) -> Void) async throws
    func startCapture() async throws
    func stopCapture() async throws
    func cleanup() async
}
