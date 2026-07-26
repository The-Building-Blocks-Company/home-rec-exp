//
//  PermissionGuidePanel.swift
//  HomeRec
//
//  Hosts the permission guide in a floating panel (BL-081).
//
//  A panel rather than a sheet or the popover, because the guide has to remain
//  readable *while System Settings is frontmost* — the popover is `.transient`
//  and dies on focus loss, and the main window may not exist at all in a
//  menu-bar app. Configuration verified by spike on macOS 26.5.2; see
//  private/reports/2026-07-26-bl081-panel-surface-spike.md.
//

import AppKit
import SwiftUI

@MainActor
final class PermissionGuidePanel: NSObject, NSWindowDelegate {

    private var panel: NSPanel?
    private let model: PermissionGuideModel
    private let onOpenSettings: () -> Void

    init(model: PermissionGuideModel, onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    /// The titlebar close button bypasses `dismiss()` entirely — AppKit closes the
    /// window directly — so without this the poll loop would keep probing
    /// `SCShareableContent` forever after the user closed the guide.
    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }

    var isVisible: Bool { panel?.isVisible ?? false }


    func show() {
        if let panel {
            panel.orderFront(nil)
            model.startPolling()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
            // `.nonactivatingPanel` keeps a click on the guide from yanking Home Rec
            // in front of the Settings window the user is working in.
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Home Rec"
        // A guide sitting behind the window it describes would be useless.
        panel.level = .floating
        // The spike found this property is not currently honoured — every panel
        // configuration survived deactivation, including ones that should have
        // hidden. Set it anyway: it is the documented lever, it costs nothing, and
        // relying on undocumented behaviour to keep the panel on screen is exactly
        // the kind of thing that breaks in a future macOS. (Note that
        // `.nonactivatingPanel` also sets it as an undocumented side effect.)
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // The poll loop rewrites the status line continuously; it must never pull
        // the keyboard away from System Settings.
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        // Follow the user across Spaces and over full-screen apps: a guide pinned
        // to the Space it opened on is invisible to someone who opens System
        // Settings on another one. Not verified against a real multi-Space setup —
        // it is the documented behaviour for utility panels and costs nothing.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        panel.contentView = NSHostingView(
            rootView: PermissionGuideView(
                model: model,
                onOpenSettings: onOpenSettings,
                onDismiss: { [weak self] in self?.dismiss() }
            )
        )
        panel.center()
        panel.orderFront(nil)

        self.panel = panel
        model.startPolling()
    }

    func dismiss() {
        model.stopPolling()
        panel?.orderOut(nil)
    }
}
