//
//  AudioRecorderTests.swift
//  HomeRecTests
//
//  BL-024: the recording path confines writer state to a single serial queue.
//  These tests assert no trailing buffers are dropped on stop and exercise
//  rapid start/stop cycles (run under Thread Sanitizer to catch data races).
//

import Testing
import Foundation
import AVFoundation
@testable import HomeRec

@MainActor
struct AudioRecorderTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("audiorecorder-test-\(UUID().uuidString).wav")
    }

    /// Build a silent, canonical non-interleaved Float32 PCM buffer with the given
    /// frame count — the same shape every `AudioCapturing` source delivers (BL-099).
    private func makePCMBuffer(frames: Int, sampleRate: Double = 48000, channels: Int = 2) -> AVAudioPCMBuffer {
        SampleBufferFixtures.makePCMBuffer(
            channels: channels, frames: frames, sampleRate: sampleRate, interleaved: false
        ) { _, _ in 0 }
    }

    /// Read the WAV `data` chunk size (UInt32 LE at offset 40).
    private func wavDataSize(at url: URL) throws -> Int {
        let b = [UInt8](try Data(contentsOf: url))
        return Int(UInt32(b[40]) | (UInt32(b[41]) << 8) | (UInt32(b[42]) << 16) | (UInt32(b[43]) << 24))
    }

    @Test("All submitted buffers are written — no trailing drops on stop")
    func noBufferDropsOnStop() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = AudioRecorder()
        try recorder.startRecording(to: url, format: .wav)

        let bufferCount = 50
        let framesPerBuffer = 64
        for _ in 0..<bufferCount {
            recorder.processAudioSample(makePCMBuffer(frames: framesPerBuffer))
        }
        try recorder.stopRecording()   // drains all in-flight buffers, then finalizes

        // 48kHz stereo Int16: frames * channels(2) * 2 bytes
        let expected = bufferCount * framesPerBuffer * 2 * 2
        #expect(try wavDataSize(at: url) == expected)
    }

    @Test("20 rapid start/stop cycles produce no corrupt-header files (TSan target)")
    func rapidStartStopCycles() throws {
        let buffersPerCycle = 5
        let framesPerBuffer = 32
        for _ in 0..<20 {
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }

            let recorder = AudioRecorder()
            try recorder.startRecording(to: url, format: .wav)
            for _ in 0..<buffersPerCycle {
                recorder.processAudioSample(makePCMBuffer(frames: framesPerBuffer))
            }
            try recorder.stopRecording()

            // Header must be valid and match the audio written (no corruption).
            let expected = buffersPerCycle * framesPerBuffer * 2 * 2
            #expect(try wavDataSize(at: url) == expected)
        }
    }

    @Test("stopRecording without an active recording throws")
    func stopWithoutStartThrows() {
        let recorder = AudioRecorder()
        #expect(throws: AudioRecorderError.self) {
            try recorder.stopRecording()
        }
    }
}
