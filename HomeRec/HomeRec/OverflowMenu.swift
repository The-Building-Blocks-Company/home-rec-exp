//
//  OverflowMenu.swift
//  HomeRec
//
//  The menu-bar overflow menu (BL-110). Secondary actions live here instead of
//  as flat buttons in the popover, which keeps the popover free for the primary
//  record/waveform surface as more features land.
//
//  Two surfaces present this menu — the "•••" button in the popover and a
//  right-click on the status item — so `entries` is the single definition both
//  render from. Adding a row in one place adds it to both.
//

import AppKit
import SwiftUI

/// One selectable row in the overflow menu.
struct OverflowAction: Identifiable {
    /// Stable across copy changes, so tests can assert an action still exists
    /// without breaking every time a title is reworded.
    let id: String
    let title: String
    /// Character for a ⌘-based shortcut ("q" → ⌘Q), or nil for no shortcut.
    /// Every shortcut in this menu is ⌘-based, so the modifier stays implicit —
    /// that's what lets one definition feed both SwiftUI's `.keyboardShortcut`
    /// and `NSMenuItem.keyEquivalent` without a translation layer between them.
    let commandKey: Character?
    let perform: @MainActor () -> Void

    init(
        id: String,
        title: String,
        commandKey: Character? = nil,
        perform: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.commandKey = commandKey
        self.perform = perform
    }
}

enum OverflowEntry {
    case action(OverflowAction)
    case separator
}

@MainActor
enum OverflowMenu {

    /// The menu's contents, in display order.
    ///
    /// Sections from other backlog items (CAPTURE SOURCE for BL-100, MONITORING
    /// for BL-131) slot in above these as they ship; the actions here are the
    /// app-level ones that were previously flat buttons in the popover footer.
    static var entries: [OverflowEntry] {
        [
            .action(OverflowAction(id: "showWindow", title: "Show Window", perform: showMainWindow)),
            .separator,
            .action(OverflowAction(id: "exportDiagnostics", title: "Export Diagnostics…", perform: Diagnostics.exportReport)),
            .action(OverflowAction(id: "reportProblem", title: "Report a Problem", perform: Diagnostics.reportProblem)),
            .action(OverflowAction(id: "about", title: "About Home Rec", perform: showAbout)),
            .separator,
            .action(OverflowAction(id: "quit", title: "Quit Home Rec", commandKey: "q") {
                NSApp.terminate(nil)
            })
        ]
    }

    /// Just the actions, separators dropped — for assertions and iteration that
    /// don't care about visual grouping.
    static var actions: [OverflowAction] {
        entries.compactMap { entry in
            if case .action(let action) = entry { return action }
            return nil
        }
    }

    // MARK: - Action implementations

    private static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // The main window is the WindowGroup titled "Home Rec" (see `HomeRecApp`).
        // Matching on title is the only stable handle AppKit has on a SwiftUI
        // scene's window, and the app deliberately outlives its closure, so the
        // window may legitimately be absent here.
        NSApp.windows.first { $0.title == "Home Rec" }?.makeKeyAndOrderFront(nil)
    }

    private static func showAbout() {
        // Activate first: as a menu-bar app Home Rec is often not frontmost, and
        // the panel would otherwise open behind whatever the user is working in.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

// MARK: - AppKit rendering (right-click on the status item)

/// Retains a menu action's closure for the lifetime of its `NSMenuItem`.
/// AppKit's target/action can't invoke a Swift closure directly, and
/// `NSMenuItem.target` doesn't retain, so the item holds this box in
/// `representedObject` to keep it alive.
private final class OverflowActionTarget: NSObject {
    private let perform: @MainActor () -> Void

    init(perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    @objc func fire(_ sender: Any?) {
        // Menu actions are always delivered on the main thread by AppKit.
        MainActor.assumeIsolated { perform() }
    }
}

@MainActor
extension OverflowMenu {

    /// The AppKit twin of the SwiftUI `Menu`, built from the same `entries`.
    static func makeNSMenu() -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .action(let action):
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(OverflowActionTarget.fire(_:)),
                    // NSMenuItem defaults its modifier mask to ⌘, matching the
                    // command-only shortcuts `OverflowAction` models.
                    keyEquivalent: action.commandKey.map(String.init) ?? ""
                )
                let target = OverflowActionTarget(perform: action.perform)
                item.target = target
                item.representedObject = target
                menu.addItem(item)
            }
        }
        return menu
    }
}

// MARK: - SwiftUI rendering (the "•••" button in the popover)

/// The popover's overflow affordance. SwiftUI's `Menu` renders as a real
/// `NSMenu` on macOS, so this gets system styling and shortcut display for free.
struct OverflowMenuButton: View {

    var body: some View {
        Menu {
            ForEach(Array(OverflowMenu.entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .separator:
                    Divider()
                case .action(let action):
                    button(for: action)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                // The glyph alone is a thin hit target; pad it out to a
                // comfortable click area without drawing any visible chrome.
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More options")
        .accessibilityLabel("More options")
    }

    @ViewBuilder
    private func button(for action: OverflowAction) -> some View {
        if let key = action.commandKey {
            Button(action.title) { action.perform() }
                .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            Button(action.title) { action.perform() }
        }
    }
}
