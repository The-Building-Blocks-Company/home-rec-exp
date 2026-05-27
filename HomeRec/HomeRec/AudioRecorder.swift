//
//  AudioRecorder.swift
//  HomeRec
//
//  Processes audio from ScreenCaptureKit and writes to WAV file
//

import Foundation
import CoreMedia
import AVFoundation
import os

/// Errors that can occur during audio recording
enum AudioRecorderError: Error, LocalizedError {
    case invalidSampleBuffer
    case formatNotSupported
    case bufferConversionFailed
    case notRecording

    var errorDescription: String? {
        switch self {
        case .invalidSampleBuffer:
            return "Invalid audio sample buffer"
        case .formatNotSupported:
            return "Audio format not supported"
        case .bufferConversionFailed:
            return "Failed to convert audio buffer"
        case .notRecording:
            return "Not currently recording"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidSampleBuffer:
            return "Check if system audio is playing"
        case .formatNotSupported:
            return "System audio format must be PCM"
        case .bufferConversionFailed:
            return "Try restarting the recording"
        case .notRecording:
            return "Start recording first"
        }
    }
}

/// Records audio from ScreenCaptureKit to WAV file
class AudioRecorder: AudioFileWriting {

    // MARK: - Properties

    private var wavWriter: WAVWriter?

    private let sampleRate: Double = 48000  // Match ScreenCaptureKit config
    private let channels: Int = 2           // Stereo

    /// Callback for waveform visualization data (downsampled amplitude values)
    var onWaveformData: (([Float]) -> Void)?

    // Processing queue for writing to disk
    private let processingQueue = DispatchQueue(
        label: "com.mdebritto.homerec.audiorecorder.processing",
        qos: .userInitiated
    )

    // MARK: - Public Methods

    /// Start recording to file
    /// - Parameter fileURL: URL where WAV file will be saved
    /// - Throws: AudioRecorderError if recording cannot start
    func startRecording(to fileURL: URL) throws {
        let writer = WAVWriter()
        try writer.createFile(at: fileURL, sampleRate: sampleRate, channels: channels)

        // Confine the writer to the processing queue: capture and stop threads
        // must never touch `wavWriter` directly, so there's no cross-thread race.
        processingQueue.sync { self.wavWriter = writer }

        Log.recorder.debug("AudioRecorder started: \(fileURL.path, privacy: .private)")
    }

    /// Process audio sample from ScreenCaptureKit
    /// - Parameter sampleBuffer: Audio sample from SCStream
    func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        // Hand off to the serial queue immediately. `wavWriter` is only ever read
        // there, so a concurrent stop cannot free it mid-read.
        processingQueue.async { [weak self] in
            guard let self, self.wavWriter != nil else { return }
            self.processSampleBuffer(sampleBuffer)
        }
    }

    /// Stop recording
    /// - Throws: AudioRecorderError if stop fails
    func stopRecording() throws {
        // Runs on the processing queue *after* all in-flight buffers (FIFO), so no
        // trailing audio is dropped and the writer is finalized exactly once.
        try processingQueue.sync {
            guard wavWriter != nil else {
                throw AudioRecorderError.notRecording
            }
            try? wavWriter?.finalize()
            wavWriter = nil
        }
    }

    /// Whether the recorder is currently writing to a file.
    var recording: Bool {
        processingQueue.sync { wavWriter != nil }
    }

    // MARK: - Private Methods

    /// Process sample buffer on background thread (orchestrator).
    /// - Parameter sampleBuffer: CMSampleBuffer from ScreenCaptureKit
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Runs ~47×/sec on the processing queue. No logging on this hot path;
        // failures drop the buffer. Conversion + downsampling are extracted into
        // `nonisolated` units (BL-007); the write stays in WAVWriter (BL-011 seam).
        guard let wavWriter = wavWriter else { return }
        guard let pcmBuffer = AudioSampleConverter.makePCMBuffer(from: sampleBuffer) else { return }

        // Waveform visualization (skip the work entirely when nothing is listening).
        if let onWaveformData = onWaveformData {
            let waveformSamples = WaveformDownsampler.downsample(pcmBuffer)
            DispatchQueue.main.async {
                onWaveformData(waveformSamples)
            }
        }

        // Write to WAV. Errors intentionally not logged here (hot path).
        try? wavWriter.writeBuffer(pcmBuffer)
    }
}
