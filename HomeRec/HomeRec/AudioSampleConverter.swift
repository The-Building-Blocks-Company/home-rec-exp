//
//  AudioSampleConverter.swift
//  HomeRec
//
//  Converts a ScreenCaptureKit CMSampleBuffer into a non-interleaved Float32
//  AVAudioPCMBuffer. Extracted from AudioRecorder so it can be unit-tested in
//  isolation (BL-007). Pure and `nonisolated` — it runs on the recorder's
//  processing queue, never the main actor, and touches no shared state.
//

import Foundation
import CoreMedia
import AVFoundation

enum AudioSampleConverter {

    /// Build a non-interleaved Float32 PCM buffer from a sample buffer.
    /// Returns `nil` for any unsupported/empty input (caller drops the buffer).
    nonisolated static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        guard let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamDesc.pointee.mSampleRate,
            channels: AVAudioChannelCount(streamDesc.pointee.mChannelsPerFrame),
            interleaved: false
        ) else {
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Query the required AudioBufferList size, then fetch it (with a retained
        // block buffer that must outlive the copy below — hence the defers).
        var requiredSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr else { return nil }

        let audioBufferListPtr = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { audioBufferListPtr.deallocate() }

        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPtr.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }
        defer { blockBuffer = nil }

        let audioBufferListPointer = UnsafeMutableAudioBufferListPointer(
            audioBufferListPtr.assumingMemoryBound(to: AudioBufferList.self)
        )

        guard let floatChannelData = pcmBuffer.floatChannelData else { return nil }

        let channelCount = Int(streamDesc.pointee.mChannelsPerFrame)
        let isInterleaved = (streamDesc.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0

        if isInterleaved {
            guard let buffer = audioBufferListPointer.first,
                  let srcData = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return nil
            }
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    floatChannelData[channel][frame] = srcData[frame * channelCount + channel]
                }
            }
        } else {
            for channel in 0..<min(channelCount, audioBufferListPointer.count) {
                if let srcData = audioBufferListPointer[channel].mData?.assumingMemoryBound(to: Float.self) {
                    floatChannelData[channel].update(from: srcData, count: frameCount)
                }
            }
        }

        return pcmBuffer
    }
}
