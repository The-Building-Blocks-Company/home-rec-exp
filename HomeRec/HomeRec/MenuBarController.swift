//
//  MenuBarController.swift
//  HomeRec
//
//  Manages the NSStatusItem (menu bar icon) and NSPopover for the compact UI.
//

import AppKit
import SwiftUI
import Combine

@MainActor
class MenuBarController: NSObject {

    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    init(viewModel: RecorderViewModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        // Configure popover
        let popoverView = MenuBarPopoverView()
            .environmentObject(viewModel)
        popover.contentViewController = NSHostingController(rootView: popoverView)
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.behavior = .transient

        // Configure status bar button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Home Rec")
            button.image?.isTemplate = true
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            // Right-clicks reach the action only if explicitly opted into; the
            // default is left-click alone (BL-110).
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Observe recording state to swap icon
        cancellable = viewModel.$state
            .map { $0 == .recording }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let button = self?.statusItem.button else { return }
                if isRecording {
                    let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
                    image?.isTemplate = false
                    button.image = image
                    // Tint the button with red using a content tint color
                    button.contentTintColor = .red
                } else {
                    let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Home Rec")
                    image?.isTemplate = true
                    button.image = image
                    button.contentTintColor = nil
                }
            }
    }

    /// Route a status-item click: the overflow menu on right/control-click, the
    /// popover otherwise (BL-110).
    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        let event = NSApp.currentEvent
        let showsMenu = Self.shouldShowOverflowMenu(
            type: event?.type ?? .leftMouseUp,
            modifiers: event?.modifierFlags ?? []
        )
        if showsMenu {
            showOverflowMenu()
        } else {
            togglePopover(sender)
        }
    }

    /// Whether a status-item click should open the overflow menu instead of the
    /// popover. Control-click counts as a right-click, per macOS convention.
    ///
    /// Static and pure so the routing rule can be tested without synthesising a
    /// real `NSEvent` or standing up a live status item.
    static func shouldShowOverflowMenu(
        type: NSEvent.EventType,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        if type == .rightMouseUp { return true }
        return type == .leftMouseUp && modifiers.contains(.control)
    }

    private func showOverflowMenu() {
        // The popover and the menu would otherwise overlap on screen.
        if popover.isShown {
            popover.performClose(nil)
        }

        // Attaching the menu is what gives the status item its standard
        // highlighted-while-open appearance. It has to come straight back off:
        // while a menu is attached AppKit routes every click to it and never
        // fires the button's action, which would strand the left-click popover.
        statusItem.menu = OverflowMenu.makeNSMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make the popover window key so it can receive input
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
