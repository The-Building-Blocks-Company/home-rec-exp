//
//  PermissionManager.swift
//  HomeRec
//
//  Screen Recording permission: probing current state and opening the pane where
//  the user grants it.
//

import Foundation
import ScreenCaptureKit
import AppKit

/// Permission status states
enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

/// Manages the system permissions Home Rec depends on.
class PermissionManager: PermissionProviding {

    /// Probe current permission state.
    ///
    /// For `.screenCapture` this doubles as registration: a `SCShareableContent`
    /// call is what puts Home Rec into the System Settings list in the first
    /// place, and on a fresh install it triggers the one-time system prompt.
    func checkPermission(_ kind: PermissionKind = .screenCapture) async -> PermissionStatus {
        switch kind {
        case .screenCapture:
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                return .granted
            } catch {
                return .denied
            }
        }
    }

    /// Probe, and if not granted, open the pane where the user can flip the toggle.
    ///
    /// The system prompt only ever appears once; after a deny or a dismiss there is
    /// no second chance at it, which is why the in-app guide (BL-081) is the real
    /// recovery path rather than a nicety.
    func requestPermission(_ kind: PermissionKind = .screenCapture) async -> Bool {
        if await checkPermission(kind) == .granted {
            return true
        }
        openSystemPreferences(for: kind)
        return false
    }

    /// Open System Settings at the pane for `kind`.
    ///
    /// Deep-linking to the pane is the most macOS allows — there is no API to
    /// scroll to or highlight our row, which is why the guide has to describe
    /// where to look instead.
    func openSystemPreferences(for kind: PermissionKind = .screenCapture) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
