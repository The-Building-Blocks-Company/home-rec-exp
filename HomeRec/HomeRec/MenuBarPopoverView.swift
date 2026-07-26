//
//  MenuBarPopoverView.swift
//  HomeRec
//
//  Compact popover UI shown from the menu bar icon.
//

import SwiftUI

struct MenuBarPopoverView: View {

    @EnvironmentObject var viewModel: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: logo, with secondary actions collected under "•••" (BL-110)
            HStack(alignment: .top) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                Spacer()

                OverflowMenuButton()
            }

            // Status row
            HStack(spacing: 8) {
                if viewModel.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }

                Text(viewModel.statusText)
                    .font(.custom("Archivo", size: 17, relativeTo: .headline))
                    .fontWeight(.medium)
                    .foregroundColor(viewModel.isRecording ? .red : .primary)

                Spacer()

                if viewModel.isRecording {
                    Text(viewModel.formattedDuration)
                        .font(.custom("Archivo", size: 15, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }

            // Inline error with recovery action
            if case .error = viewModel.state, let message = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.custom("Inter-Regular", size: 12, relativeTo: .caption))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let recovery = viewModel.recoverySuggestion {
                        Button(recovery.label) {
                            viewModel.performRecovery()
                        }
                        .font(.custom("Inter-Regular", size: 12, relativeTo: .caption))
                    }
                }
            }

            // Mini waveform (only while recording)
            if viewModel.isRecording {
                WaveformView(samples: viewModel.waveformSamples)
                    .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                    .frame(height: 36)
                    .animation(.easeOut(duration: 0.1), value: viewModel.waveformSamples)
            }

            // Primary action. A red "Start recording" on an app that cannot record
            // is a false affordance, so when the bundle is translocated (BL-082a)
            // the button carries the corrective action instead — and the popover
            // explains the block itself rather than spawning the floating panel
            // out of a transient surface (BL-086).
            //
            // The status row above and this explanation are title and body, not a
            // duplication: the row compresses the action, this states the fact and
            // the procedure. Accent fill rather than grey — grey is the system's
            // *disabled* costume, and this is the only thing on the surface the
            // user can do. Red is unavailable; it means "record" in this app.
            if viewModel.installLocationBlocksRecording, let message = viewModel.installNotice {
                Text(message)
                    .font(.custom("Inter-Regular", size: 12, relativeTo: .caption))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                    viewModel.revealAppInFinder()
                }) {
                    Text("Reveal in Finder")
                        .font(.custom("Archivo", size: 13, relativeTo: .body))
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    Task {
                        await viewModel.toggleRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                        Text(viewModel.isRecording ? "Stop recording" : "Start recording")
                            .font(.custom("Archivo", size: 13, relativeTo: .body))
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            // Last recording info. Hidden while blocked: its "Reveal" targets the
            // recording, and the block's "Reveal in Finder" targets the app bundle
            // — two near-identical affordances with different targets, 40pt apart
            // on a 280pt surface. The file stays where it is; only the row waits.
            if let url = viewModel.lastRecordingURL,
               !viewModel.isRecording,
               !viewModel.installLocationBlocksRecording {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.secondary)
                    Text(url.lastPathComponent)
                        .font(.custom("Archivo", size: 12, relativeTo: .caption))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Reveal") {
                        viewModel.revealInFinder()
                    }
                    .font(.custom("Inter-Regular", size: 12, relativeTo: .caption))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
            }

        }
        .padding(16)
        .frame(width: 280)
    }
}
