//
//  PermissionProviding.swift
//  HomeRec
//
//  Abstraction over Screen Recording permission so the view model can be
//  tested with a fake provider instead of the real system permission.
//

import Foundation

/// Supplies Screen Recording permission state and the request flow.
/// Implemented by `PermissionManager`.
@MainActor
protocol PermissionProviding {
    func checkPermission() async -> PermissionStatus
    func requestPermission() async -> Bool
    func openSystemPreferences()
}
