//
//  RecordingState.swift
//  HomeRec
//
//  Single source of truth for the recording lifecycle. The view model owns
//  one RecordingState and the UI derives entirely from it, so "UI says
//  recording while nothing is written" is no longer representable.
//

import Foundation

/// A recoverable failure surfaced to the user during recording.
/// Richer copy and recovery actions are handled separately.
enum RecorderError: Error, Equatable, Sendable {
    case startFailed(String)
    case stopFailed(String)
    case streamFailed(String)

    /// User-facing message describing the failure.
    nonisolated var message: String {
        switch self {
        case .startFailed(let detail):
            return "Failed to start recording: \(detail)"
        case .stopFailed(let detail):
            return "Failed to stop recording: \(detail)"
        case .streamFailed(let detail):
            return "Recording stopped unexpectedly: \(detail)"
        }
    }
}

/// The lifecycle states of a recording session.
enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case stopping
    case error(RecorderError)
    case recovering

    /// Whether moving to `next` is a legal transition from `self`.
    /// Illegal transitions (e.g. `idle → stopping`) return `false`.
    nonisolated func canTransition(to next: RecordingState) -> Bool {
        switch (self, next) {
        case (.idle, .starting):
            return true
        case (.starting, .recording),
             (.starting, .error),
             (.starting, .idle):
            return true
        case (.recording, .stopping),
             (.recording, .error),
             (.recording, .recovering):
            return true
        case (.stopping, .idle),
             (.stopping, .error):
            return true
        case (.error, .idle),
             (.error, .starting):
            return true
        case (.recovering, .recording),
             (.recovering, .stopping),
             (.recovering, .error):
            return true
        default:
            return false
        }
    }
}
