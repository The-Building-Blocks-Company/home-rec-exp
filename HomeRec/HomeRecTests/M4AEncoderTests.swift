//
//  M4AEncoderTests.swift
//  HomeRecTests
//
//  BL-012: drive M4AEncoder (through the AudioFileEncoder protocol) with a
//  synthetic Float32 PCM stream and assert the produced .m4a is a valid,
//  decodable AAC file with the right channel count and a duration matching the
//  input. AAC is lossy, so we assert decodability + duration tolerance, never
//  bytes (the format-agnostic hook noted in AudioFileEncoderTests).
//

import Testing
import Foundation
import AVFoundation
@testable import HomeRec

@MainActor
struct M4AEncoderTests {

    private let inputSampleRate: Double = 48_000
    private let channels = 2
    private let bufferCount = 48
    private let framesPerBuffer = 1_024   // 48 × 1024 = 49,152 frames ≈ 1.024 s

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("m4a-test-\(UUID().uuidString).m4a")
    }

    /// A non-interleaved Float32 buffer (what the real pipeline feeds), filled
    /// with a mild non-zero signal.
    private func buffer(_ index: Int) -> AVAudioPCMBuffer {
        SampleBufferFixtures.makePCMBuffer(
            channels: channels, frames: framesPerBuffer,
            sampleRate: inputSampleRate, interleaved: false
        ) { ch, frame in
            let n = index * self.framesPerBuffer + frame
            let v = Float(sin(Double(n) * 0.02)) * 0.4
            return ch == 0 ? v : -v
        }
    }

    private func encodeStream(to url: URL) throws {
        let encoder: any AudioFileEncoder = M4AEncoder()
        try encoder.createFile(at: url, sampleRate: inputSampleRate, channels: channels)
        for i in 0..<bufferCount {
            try encoder.writeBuffer(buffer(i))
        }
        try encoder.finalize()
    }

    @Test("Encodes a synthetic stream to a valid, decodable stereo .m4a")
    func producesValidM4A() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try encodeStream(to: url)

        // File exists and has real content.
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 0)

        // Decodable as audio, stereo.
        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.channelCount == AVAudioChannelCount(channels))

        // Duration matches the input within tolerance (AAC adds encoder
        // priming/padding, so allow a small delta rather than exact equality).
        let expected = Double(bufferCount * framesPerBuffer) / inputSampleRate
        let actual = Double(file.length) / file.fileFormat.sampleRate
        #expect(abs(actual - expected) < 0.15)
    }

    @Test("Output is AAC at the configured 44.1kHz")
    func outputIsAAC44k() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try encodeStream(to: url)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 44_100)
    }

    @Test("finalize before createFile throws")
    func finalizeBeforeCreateThrows() {
        let encoder: any AudioFileEncoder = M4AEncoder()
        #expect(throws: M4AEncoderError.notOpen) {
            try encoder.finalize()
        }
    }
}
