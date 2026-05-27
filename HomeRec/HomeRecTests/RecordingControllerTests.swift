//
//  RecordingControllerTests.swift
//  HomeRecTests
//
//  BL-015: the controller threads the chosen AudioFormat into both the file
//  path (extension) and the recorder (encoder). Uses the injectable mock seams.
//

import Testing
import Foundation
@testable import HomeRec

@MainActor
struct RecordingControllerTests {

    private func makeController(
        recorder: MockAudioFileWriting? = nil,
        capture: MockAudioCapturing? = nil
    ) -> RecordingController {
        RecordingController(
            captureManager: capture ?? MockAudioCapturing(),
            audioRecorder: recorder ?? MockAudioFileWriting(),
            saveLocation: MockSaveLocationProviding(directory: FileManager.default.temporaryDirectory)
        )
    }

    @Test("generateFilePath uses the format's extension", arguments: [AudioFormat.wav, .m4a])
    func filePathExtensionFollowsFormat(_ format: AudioFormat) {
        let url = makeController().generateFilePath(format: format)
        #expect(url.pathExtension == format.fileExtension)
    }

    @Test("startRecording threads the format into the recorder and the file URL")
    func startThreadsFormat() async throws {
        let recorder = MockAudioFileWriting()
        let controller = makeController(recorder: recorder)

        let url = try await controller.startRecording(format: .m4a)

        #expect(recorder.lastStartFormat == .m4a)
        #expect(url.pathExtension == "m4a")
        #expect(controller.recordingURL?.pathExtension == "m4a")
    }
}
