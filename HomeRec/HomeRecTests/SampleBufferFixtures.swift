//
//  SampleBufferFixtures.swift
//  HomeRecTests
//
//  Shared synthetic audio fixtures for BL-007 tests: Float32 PCM buffers filled
//  with known (non-zero) data, and CMSampleBuffers in both interleaved and
//  non-interleaved layouts. The non-interleaved path is built from an
//  AVAudioPCMBuffer (which guarantees a correct per-channel AudioBufferList) and
//  wrapped via CMSampleBufferSetDataBufferFromAudioBufferList.
//

import Foundation
import AVFoundation
import CoreMedia

enum SampleBufferFixtures {

    /// A Float32 PCM buffer (interleaved or not) with each sample set by `fill(channel, frame)`.
    static func makePCMBuffer(
        channels: Int,
        frames: Int,
        sampleRate: Double = 48000,
        interleaved: Bool,
        fill: (_ channel: Int, _ frame: Int) -> Float
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: interleaved
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(frames, 1)))!
        buffer.frameLength = AVAudioFrameCount(frames)

        if frames > 0 {
            if interleaved {
                let abl = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                let ptr = abl[0].mData!.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        ptr[frame * channels + channel] = fill(channel, frame)
                    }
                }
            } else {
                let channelData = buffer.floatChannelData!
                for channel in 0..<channels {
                    for frame in 0..<frames {
                        channelData[channel][frame] = fill(channel, frame)
                    }
                }
            }
        }
        return buffer
    }

    /// Wrap a PCM buffer into a CMSampleBuffer, preserving its (non-)interleaved layout.
    static func makeSampleBuffer(from pcm: AVAudioPCMBuffer) -> CMSampleBuffer {
        var asbd = pcm.format.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(pcm.format.sampleRate)),
            presentationTimeStamp: CMTime(value: 0, timescale: CMTimeScale(pcm.format.sampleRate)),
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(pcm.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcm.audioBufferList
        )
        return sampleBuffer!
    }

    /// Convenience: an interleaved CMSampleBuffer filled via `fill`.
    static func interleaved(frames: Int, channels: Int = 2, sampleRate: Double = 48000, fill: (Int, Int) -> Float) -> CMSampleBuffer {
        makeSampleBuffer(from: makePCMBuffer(channels: channels, frames: frames, sampleRate: sampleRate, interleaved: true, fill: fill))
    }

    /// Convenience: a non-interleaved CMSampleBuffer filled via `fill`.
    static func nonInterleaved(frames: Int, channels: Int = 2, sampleRate: Double = 48000, fill: (Int, Int) -> Float) -> CMSampleBuffer {
        makeSampleBuffer(from: makePCMBuffer(channels: channels, frames: frames, sampleRate: sampleRate, interleaved: false, fill: fill))
    }
}
