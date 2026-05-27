//
//  StreamFailureTests.swift
//  HomeRecTests
//
//  BL-020: a capture-stream failure must reach the view model (transition to
//  .error) and finalize the partial recording exactly once.
//

import Testing
import Foundation
@testable import HomeRec

@MainActor
struct StreamFailureTests {

    @Test("Stream failure transitions the VM to .error and finalizes the recording once")
    func streamFailureFinalizesAndErrors() async {
        let mockCapturer = MockAudioCapturing()
        let mockWriter = MockAudioFileWriting()
        let controller = RecordingController(captureManager: mockCapturer, audioRecorder: mockWriter)
        let viewModel = RecorderViewModel(
            controller: controller,
            permissions: MockPermissionProviding(.granted),
            clock: ManualClock()
        )

        await viewModel.startRecording()
        #expect(viewModel.state == .recording)

        await confirmation("partial recording finalized exactly once") { finalized in
            mockWriter.onStop = { finalized() }
            mockCapturer.simulateStreamError("Screen Recording permission revoked")

            // The error state is published synchronously on the failure callback.
            #expect(viewModel.state == .error(.streamFailed("Screen Recording permission revoked")))

            // Let the (main-actor) finalize task run to completion.
            while mockWriter.stopCount == 0 {
                await Task.yield()
            }
        }

        #expect(mockWriter.stopCount == 1)
        #expect(viewModel.isRecording == false)
    }

    @Test("A stream error while idle is ignored (no spurious error state)")
    func streamErrorWhileIdleIsIgnored() {
        let mockCapturer = MockAudioCapturing()
        let mockWriter = MockAudioFileWriting()
        let controller = RecordingController(captureManager: mockCapturer, audioRecorder: mockWriter)
        let viewModel = RecorderViewModel(
            controller: controller,
            permissions: MockPermissionProviding(.granted),
            clock: ManualClock()
        )

        #expect(viewModel.state == .idle)
        mockCapturer.simulateStreamError("spurious")
        #expect(viewModel.state == .idle)
        #expect(mockWriter.stopCount == 0)
    }
}
