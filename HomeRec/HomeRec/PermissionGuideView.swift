//
//  PermissionGuideView.swift
//  HomeRec
//
//  Contents of the permission guide panel (BL-081).
//
//  Deliberately plain: no System Settings screenshot (macOS has already renamed
//  these panes once — a stale screenshot misleads worse than none), no app icon
//  or exact-name row (the blocker is the *section*, not the name), no step
//  numbering. One reassurance, one instruction, one status line.
//

import SwiftUI

struct PermissionGuideView: View {

    @ObservedObject var model: PermissionGuideModel
    var onOpenSettings: () -> Void
    var onDismiss: () -> Void

    private var title: String {
        switch model.state {
        case .granted:      return "Permission granted"
        case .timedOut:     return "Still waiting"
        case .awaitingGrant: return "Waiting for permission"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.custom("Archivo", size: 15, relativeTo: .headline))
                .fontWeight(.medium)

            if model.state == .granted {
                Text("You're ready to record.")
                    .font(.custom("Inter-Regular", size: 12, relativeTo: .body))
                    .foregroundColor(.secondary)
            } else if model.state == .timedOut {
                // Stopped checking rather than probe forever. Say so plainly and
                // offer the way back — a panel that quietly stopped working would
                // strand someone who granted permission a minute too late.
                Text("Home Rec stopped checking. If you've granted permission, pick it up again below.")
                    .font(.custom("Inter-Regular", size: 12, relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // The navigation instruction. Naming the section the user would
                // otherwise search — and not find Home Rec in — is the whole point
                // of this panel; see PermissionKind.navigationHint.
                Text(model.navigationHint)
                    .font(.custom("Inter-Regular", size: 12, relativeTo: .body))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Home Rec never records your screen — macOS just files audio capture under that name.")
                    .font(.custom("Inter-Regular", size: 11, relativeTo: .caption))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Two surfaces asking one question at the same instant is the
                // classic "which one is real?" trust break. Only shown when a
                // system prompt is actually likely, so it disappears on return
                // visits (BL-087).
                if model.promptLikely {
                    Text("If macOS shows its own permission dialog, that's this same request — answering it there is enough.")
                        .font(.custom("Inter-Regular", size: 12, relativeTo: .body))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The residual empty-list case. An app only joins that list once
                // it has asked, and the list does not always refresh live — so a
                // user can still arrive to no row. One quiet line turns a dead end
                // into a recoverable one (BL-087).
                Text("If Home Rec isn't in the list, click + and add it from your Applications folder.")
                    .font(.custom("Inter-Regular", size: 11, relativeTo: .caption))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                switch model.state {
                case .granted:
                    EmptyView()
                case .timedOut:
                    Button("Check again") { model.resumePolling() }
                case .awaitingGrant:
                    // Disabled while the registering probe is in flight, so the
                    // click cannot be fired twice. No spinner: the probe is
                    // typically well under the ~100 ms that makes waiting felt.
                    Button("Open System Settings", action: onOpenSettings)
                        .disabled(model.isOpeningSettings)
                }
                Spacer()
                Button(model.state == .granted ? "Done" : "Close", action: onDismiss)
            }
            .font(.custom("Inter-Regular", size: 12, relativeTo: .caption))
        }
        .padding(18)
        .frame(width: 340)
    }
}
