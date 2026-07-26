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

            // Record / Stop button
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

            // Last recording info
            if let url = viewModel.lastRecordingURL, !viewModel.isRecording {
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
