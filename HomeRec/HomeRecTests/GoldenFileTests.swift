//
//  GoldenFileTests.swift
//  HomeRecTests
//
//  BL-051 / BL-007 behavior guard: feed a deterministic, non-zero buffer
//  sequence through the full AudioRecorder and assert the produced WAV's PCM
//  bytes exactly match an independently-computed reference. Interleaved and
//  non-interleaved inputs must produce identical output. Uses the recorder's
//  production format (48kHz stereo, the header it always writes).
//

import Testing
import Foundation
import AVFoundation
import CoreMedia
@testable import HomeRec

@MainActor
struct GoldenFileTests {

    private let bufferCount = 5
    private let framesPerBuffer = 64
    private let channels = 2

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("golden-\(UUID().uuidString).wav")
    }

    /// Deterministic, channel-distinct sample in [-1, 1).
    private func sample(buffer b: Int, channel ch: Int, frame f: Int) -> Float {
        let n = b * framesPerBuffer + f
        let base = Float(n % 200) / 100.0 - 1.0   // -1.0 … 0.99
        return ch == 0 ? base : -base
    }

    /// The WAV `data` bytes we expect: interleaved Int16 LE (frame-major), using
    /// the exact clamp+scale WAVWriter applies.
    private func expectedPCMBytes() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(bufferCount * framesPerBuffer * channels * 2)
        for b in 0..<bufferCount {
            for f in 0..<framesPerBuffer {
                for ch in 0..<channels {
                    let clamped = max(-1.0, min(1.0, sample(buffer: b, channel: ch, frame: f)))
                    let u = UInt16(bitPattern: Int16(clamped * 32767.0))
                    bytes.append(UInt8(u & 0xff))
                    bytes.append(UInt8(u >> 8))
                }
            }
        }
        return bytes
    }

    private func recordedPCMBytes(interleaved: Bool) throws -> [UInt8] {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = AudioRecorder()
        try recorder.startRecording(to: url)
        for b in 0..<bufferCount {
            let sb: CMSampleBuffer = interleaved
                ? SampleBufferFixtures.interleaved(frames: framesPerBuffer, channels: channels) { ch, f in sample(buffer: b, channel: ch, frame: f) }
                : SampleBufferFixtures.nonInterleaved(frames: framesPerBuffer, channels: channels) { ch, f in sample(buffer: b, channel: ch, frame: f) }
            recorder.processAudioSample(sb)
        }
        try recorder.stopRecording()   // drains the queue, then finalizes

        let all = [UInt8](try Data(contentsOf: url))
        return Array(all[44...])   // strip the 44-byte header
    }

    @Test("Interleaved input → expected WAV PCM bytes (golden)")
    func goldenInterleaved() throws {
        #expect(try recordedPCMBytes(interleaved: true) == expectedPCMBytes())
    }

    @Test("Non-interleaved input → identical WAV PCM bytes")
    func goldenNonInterleaved() throws {
        #expect(try recordedPCMBytes(interleaved: false) == expectedPCMBytes())
    }
}
