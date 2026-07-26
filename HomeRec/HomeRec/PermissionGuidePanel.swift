//
//  PermissionGuidePanel.swift
//  HomeRec
//
//  Hosts the permission guide on the shared floating panel (BL-081).
//
//  The window configuration itself — and the reason behind each value it sets —
//  now lives in `FloatingPanelHost`, because BL-082's translocation notice needs
//  the identical surface and a second hand-rolled NSPanel would drift from this
//  one within a release.
//

import AppKit
import SwiftUI

@MainActor
final class PermissionGuidePanel {

    private let model: PermissionGuideModel
    private let host: FloatingPanelHost

    init(model: PermissionGuideModel, onOpenSettings: @escaping () -> Void) {
        self.model = model
        // The content needs to call back into a `self` that doesn't exist yet;
        // routing through a mutable box keeps the capture weak once it does.
        let dismissBox = CallbackBox()
        self.host = FloatingPanelHost(title: "Home Rec", width: 340) {
            AnyView(
                PermissionGuideView(
                    model: model,
                    onOpenSettings: onOpenSettings,
                    onDismiss: { dismissBox.callback?() }
                )
            )
        }
        dismissBox.callback = { [weak self] in self?.dismiss() }
        // The titlebar close button bypasses `dismiss()` entirely — AppKit closes
        // the window directly — so without this the poll loop would keep probing
        // `SCShareableContent` forever after the user closed the guide.
        host.onWillClose = { [weak model] in model?.stopPolling() }
    }

    var isVisible: Bool { host.isVisible }

    func show() {
        host.show()
        model.startPolling()
    }

    func dismiss() {
        model.stopPolling()
        host.dismiss()
    }
}

/// Late-bound callback holder, so a view built during `init` can invoke a method
/// on the object being initialised without capturing it strongly.
@MainActor
final class CallbackBox {
    var callback: (() -> Void)?
}
