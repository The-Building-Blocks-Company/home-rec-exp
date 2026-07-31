//
//  RecoveryViewModel.swift
//  HomeRec
//
//  BL-140: state for the Recover Recordings window. Deliberately thin — the
//  detection and repair logic lives behind `AudioFileRecovering`, so this type
//  only orchestrates and reports.
//

import Foundation
import Combine
import AppKit

@MainActor
final class RecoveryViewModel: ObservableObject {

    @Published private(set) var recordings: [RecoverableRecording] = []
    @Published private(set) var hasScanned = false
    /// Set when an action fails, so the window can say so rather than silently
    /// doing nothing — the same honesty BL-016 added to the stop path.
    @Published var errorMessage: String?

    private let scanner: RecoveryScanning
    /// The file being written right now, if any. A live recording is unfinalized
    /// by definition and must never be offered for recovery.
    private let inProgressURL: () -> URL?

    init(scanner: RecoveryScanning, inProgressURL: @escaping () -> URL? = { nil }) {
        self.scanner = scanner
        self.inProgressURL = inProgressURL
    }

    var isEmpty: Bool { hasScanned && recordings.isEmpty }

    func refresh() {
        recordings = scanner.scan(excluding: inProgressURL())
        hasScanned = true
    }

    func recover(_ recording: RecoverableRecording) {
        do {
            try RecoveryScanner.recover(recording)
            refresh()   // a repaired file is no longer unfinalized, so it drops off
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealInFinder(_ recording: RecoverableRecording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    func moveToTrash(_ recording: RecoverableRecording) {
        do {
            try FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Display helpers

    func sizeText(_ recording: RecoverableRecording) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(recording.byteCount), countStyle: .file)
    }

    func dateText(_ recording: RecoverableRecording) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: recording.modifiedAt)
    }
}
