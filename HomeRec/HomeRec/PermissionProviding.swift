//
//  PermissionProviding.swift
//  HomeRec
//
//  Abstraction over system permission state so the view model can be tested
//  with a fake provider instead of the real system permission.
//

import Foundation

/// Supplies permission state and the request flow. Implemented by `PermissionManager`.
///
/// Every method takes a `PermissionKind` with a default, so today's single-permission
/// call sites read unchanged while BL-130's microphone permission slots in without
/// touching this seam again. The *copy* for each kind lives on `PermissionKind`
/// rather than here: it's pure data with no system state behind it, so routing it
/// through a mockable protocol would only force every test double to restate the
/// same strings.
@MainActor
protocol PermissionProviding {
    func checkPermission(_ kind: PermissionKind) async -> PermissionStatus
    func requestPermission(_ kind: PermissionKind) async -> Bool
    func openSystemPreferences(for kind: PermissionKind)
}

extension PermissionProviding {
    func checkPermission() async -> PermissionStatus {
        await checkPermission(.screenCapture)
    }

    func requestPermission() async -> Bool {
        await requestPermission(.screenCapture)
    }

    func openSystemPreferences() {
        openSystemPreferences(for: .screenCapture)
    }
}
