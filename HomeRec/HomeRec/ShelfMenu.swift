//
//  ShelfMenu.swift
//  HomeRec
//
//  Shared chrome for the settings-shelf controls (BL-015). Both the save-location
//  and output-format controls are "a quiet borderless pop-up": a line of
//  secondary caption text plus an up/down chevron, no border, hidden menu
//  indicator. This view owns that chrome (font, color, chevron, tooltip,
//  accessibility) so the controls stay visually identical; each caller supplies
//  only its own menu items via `content`.
//

import SwiftUI

/// A borderless, secondary-styled pop-up menu for the bottom settings shelf.
///
/// Renders `title` (value included, e.g. `"Saving to Desktop"` or
/// `"Recording as WAV"`) in the shelf's caption font next to a
/// `chevron.up.chevron.down`, with no button border and the system menu
/// indicator hidden. The pop-up's items come from `content`.
///
/// - Note: VoiceOver reads `accessibilityLabel` (what the control changes) and
///   `accessibilityValue` (the current selection) separately, so pass the value
///   to `accessibilityValue` rather than baking it into the label.
struct ShelfMenu<MenuContent: View>: View {

    /// The full line shown in the shelf, value included.
    let title: String
    /// Hover tooltip (e.g. the full save path, or the format description).
    let help: String
    /// VoiceOver label: what the control changes (e.g. "Save location").
    let accessibilityLabel: String
    /// VoiceOver value: the current selection (e.g. "Desktop", "WAV (Lossless)").
    let accessibilityValue: String
    /// The pop-up's items — typically `Button`s that mutate view-model state.
    @ViewBuilder var content: () -> MenuContent

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.custom("Inter-Regular", size: 12, relativeTo: .caption))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }
}
