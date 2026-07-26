//
//  AudioSourceManager.swift
//  HomeRec
//
//  Owns capture-source selection for BL-100: persists the user's choice,
//  enumerates currently running apps for the picker, and validates a source
//  is still capturable before a recording starts.
//

import Foundation
import ScreenCaptureKit

/// A running app the capture-source picker can offer, as seen by ScreenCaptureKit.
struct RunningAppInfo: Identifiable, Sendable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let applicationName: String
}

enum AudioSourceError: Error, LocalizedError, Equatable {
    case appNotRunning(String)

    var errorDescription: String? {
        switch self {
        case .appNotRunning(let bundleID):
            return "The selected app (\(bundleID)) is not currently running."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .appNotRunning:
            return "Open the app, or choose a different capture source."
        }
    }
}

@MainActor
protocol AudioSourceProviding: AnyObject {
    /// The persisted capture source. Defaults to `.systemAll` on first run.
    var selectedSource: AudioSource { get }
    func setSelectedSource(_ source: AudioSource)
    /// Throws `AudioSourceError` if `source` cannot be captured right now
    /// (e.g. the selected app isn't running). Call before starting capture.
    func validate(_ source: AudioSource) async throws
    /// Currently running apps the picker can offer, excluding Home Rec itself.
    ///
    /// ⚠️ **This calls `SCShareableContent` directly, bypassing `PermissionProviding`.**
    /// That means it can raise the system permission dialog and registers the app
    /// with TCC — so it must never run on a zero-click path (BL-085). It is safe
    /// today only because nothing reaches it without a Record click.
    ///
    /// **Precondition for BL-100's source picker:** SwiftUI evaluates `Menu`
    /// content eagerly in several situations, so a naïvely wired picker would call
    /// this on *popover appearance* — a zero-click prompt. Enumerate only on an
    /// explicit submenu open, and only when `permissionStatus == .granted`.
    func availableApps() async throws -> [RunningAppInfo]
}

@MainActor
final class AudioSourceManager: AudioSourceProviding {
    private let defaults: UserDefaults
    private let key = "selectedAudioSource"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedSource: AudioSource {
        guard let data = defaults.data(forKey: key),
              let source = try? JSONDecoder().decode(AudioSource.self, from: data) else {
            return .systemAll
        }
        return source
    }

    func setSelectedSource(_ source: AudioSource) {
        guard let data = try? JSONEncoder().encode(source) else { return }
        defaults.set(data, forKey: key)
    }

    func validate(_ source: AudioSource) async throws {
        switch source {
        case .systemAll:
            return
        case .app(let bundleID):
            let apps = try await availableApps()
            guard apps.contains(where: { $0.bundleID == bundleID }) else {
                throw AudioSourceError.appNotRunning(bundleID)
            }
        }
    }

    func availableApps() async throws -> [RunningAppInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let ownBundleID = Bundle.main.bundleIdentifier
        return content.applications
            .filter { $0.bundleIdentifier != ownBundleID }
            .map { RunningAppInfo(bundleID: $0.bundleIdentifier, applicationName: $0.applicationName) }
    }
}
