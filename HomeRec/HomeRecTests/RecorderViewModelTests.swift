//
//  RecorderViewModelTests.swift
//  HomeRecTests
//
//  BL-005: view-model lifecycle tests — state transitions, permission gating,
//  error handling, duration timing (via injected clock), and stream-failure.
//  Deterministic, no hardware/permission, no sleeps.
//

import Testing
import Foundation
@testable import HomeRec

/// A controllable error with a known message for assertions.
private struct TestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
struct RecorderViewModelTests {

    private func makeViewModel(
        controller: MockRecordingControlling? = nil,
        permission: PermissionStatus = .granted,
        clock: ManualClock? = nil
    ) -> RecorderViewModel {
        RecorderViewModel(
            controller: controller ?? MockRecordingControlling(),
            permissions: MockPermissionProviding(permission),
            clock: clock ?? ManualClock()
        )
    }

    @Test("Initial state is idle")
    func initialStateIsIdle() {
        let viewModel = makeViewModel()
        #expect(viewModel.state == .idle)
        #expect(viewModel.isRecording == false)
    }

    @Test("startRecording with granted permission transitions to recording")
    func startWithPermissionRecords() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(controller: controller, permission: .granted)

        await viewModel.startRecording()

        #expect(viewModel.state == .recording)
        #expect(viewModel.isRecording)
        #expect(controller.startCount == 1)
        #expect(viewModel.lastRecordingURL == controller.fileURL)
    }

    @Test("startRecording with denied permission does not record and surfaces an error")
    func startWithoutPermissionDoesNotRecord() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(controller: controller, permission: .denied)

        await viewModel.startRecording()

        #expect(viewModel.state == .idle)
        #expect(controller.startCount == 0)
        #expect(viewModel.showError)
    }

    @Test("stopRecording returns to idle and resets the waveform")
    func stopReturnsToIdle() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(controller: controller)

        await viewModel.startRecording()
        #expect(viewModel.state == .recording)

        await viewModel.stopRecording()

        #expect(viewModel.state == .idle)
        #expect(controller.stopCount == 1)
        #expect(viewModel.waveformSamples == Array(repeating: 0, count: 200))
    }

    @Test("A controller start error transitions to .error with a message")
    func startErrorSurfacesErrorState() async {
        let controller = MockRecordingControlling()
        controller.startError = TestError(message: "no capture device")
        let viewModel = makeViewModel(controller: controller)

        await viewModel.startRecording()

        #expect(viewModel.state == .error(.startFailed("no capture device")))
        #expect(viewModel.errorMessage == "Failed to start recording: no capture device")
        #expect(viewModel.showError)
    }

    @Test("Duration advances using the injected clock, not a real timer")
    func durationAdvancesWithClock() async {
        let clock = ManualClock()
        let viewModel = makeViewModel(clock: clock)

        await viewModel.startRecording()
        #expect(viewModel.duration == 0)
        #expect(clock.isTicking)

        clock.advance(by: 5)
        #expect(viewModel.duration == 5)

        clock.advance(by: 2.5)
        #expect(viewModel.duration == 7.5)

        await viewModel.stopRecording()
        #expect(clock.isTicking == false)
    }

    @Test("Stream-failure callback transitions to .error and finalizes once")
    func streamFailureHandled() async {
        let controller = MockRecordingControlling()
        let viewModel = makeViewModel(controller: controller)

        await viewModel.startRecording()
        #expect(viewModel.state == .recording)

        await confirmation("controller finalized exactly once") { finalized in
            controller.onFinalize = { finalized() }
            controller.emitStreamError("display went to sleep")

            #expect(viewModel.state == .error(.streamFailed("display went to sleep")))

            while controller.finalizeCount == 0 {
                await Task.yield()
            }
        }

        #expect(controller.finalizeCount == 1)
        #expect(viewModel.isRecording == false)
    }
}
