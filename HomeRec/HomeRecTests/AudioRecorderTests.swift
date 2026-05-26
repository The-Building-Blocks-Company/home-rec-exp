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
import CoreMedia
@testable import HomeRec

@MainActor
struct AudioRecorderTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("audiorecorder-test-\(UUID().uuidString).wav")
    }

    /// Build a silent interleaved Float32 CMSampleBuffer with the given frame count,
    /// matching the layout ScreenCaptureKit delivers.
    private func makeSampleBuffer(frames: Int, sampleRate: Double = 48000, channels: Int = 2) -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 4),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * 4),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        let dataByteCount = frames * channels * 4
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataByteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataByteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: dataByteCount)

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(value: 0, timescale: CMTimeScale(sampleRate)),
            decodeTimeStamp: .invalid
        )
        var sampleSize = channels * 4
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frames),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer!
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
        try recorder.startRecording(to: url)

        let bufferCount = 50
        let framesPerBuffer = 64
        for _ in 0..<bufferCount {
            recorder.processAudioSample(makeSampleBuffer(frames: framesPerBuffer))
        }
        try recorder.stopRecording()   // drains all in-flight buffers, then finalizes

        // 48kHz stereo Int16: frames * channels(2) * 2 bytes
        let expected = bufferCount * framesPerBuffer * 2 * 2
        #expect(try wavDataSize(at: url) == expected)
    }

    @Test("Rapid start/stop cycles complete cleanly (TSan target)")
    func rapidStartStopCycles() throws {
        for _ in 0..<20 {
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }

            let recorder = AudioRecorder()
            try recorder.startRecording(to: url)
            for _ in 0..<5 {
                recorder.processAudioSample(makeSampleBuffer(frames: 32))
            }
            try recorder.stopRecording()
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
