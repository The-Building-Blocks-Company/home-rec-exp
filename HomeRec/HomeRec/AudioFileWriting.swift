//
//  AudioFileWriting.swift
//  HomeRec
//
//  Abstraction over the object that turns captured buffers into an audio
//  file on disk, so the workflow can be tested without real capture.
//

import Foundation
import CoreMedia

/// Writes captured audio buffers to a file. Implemented by `AudioRecorder`.
@MainActor
protocol AudioFileWriting: AnyObject, Sendable {
    var onWaveformData: (([Float]) -> Void)? { get set }
    var recording: Bool { get }
    func startRecording(to fileURL: URL) throws
    func processAudioSample(_ sampleBuffer: CMSampleBuffer)
    func stopRecording() throws
}
