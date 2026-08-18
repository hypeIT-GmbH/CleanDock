//
//  CleanupFooterView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import CleanDockCore
import SwiftUI

/// The fixed footer bar with the primary "Load Profile" button (⌘⏎), the
/// "Undo" button and the post-cleanup feedback (success, skipped apps).
struct CleanupFooterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profile: Profile
    let isManaged: Bool

    @State private var showingConfirmation = false
    /// Incremented on every apply attempt to retrigger the checkmark bounce -
    /// repeated applies produce Equatable-equal feedback values that would
    /// not re-animate on their own.
    @State private var applyCount = 0

    private var feedback: AppModel.CleanupFeedback? {
        guard let feedback = model.feedback, feedback.profileID == profile.id else {
            return nil
        }
        return feedback
    }

    var body: some View {
        bar
            .padding(12)
    }

    @ViewBuilder
    private var bar: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Button {
                model.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .help("Restore the Dock from the most recent backup")

            if let feedback {
                FeedbackView(feedback: feedback, bounceTrigger: applyCount)
            }

            Spacer()

            cleanupButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Drives the FeedbackView's transition: without an animation on the
        // container observing the change, the insert/remove would pop in
        // hard and the transition below would never run. Safe here - the
        // footer lives in the main window, not in the menu graph.
        .animation(reduceMotion ? nil : .default, value: feedback)
    }

    private var cleanupButton: some View {
        Button {
            showingConfirmation = true
        } label: {
            Label("Load Profile", systemImage: "sparkles")
                .fontWeight(.semibold)
        }
        .keyboardShortcut(.return, modifiers: .command)
        .controlSize(.large)
        .help("Replace the Dock with exactly the apps of this profile (⌘⏎)")
        .popover(isPresented: $showingConfirmation, arrowEdge: .top) {
            confirmationPopover
        }
        .prominentButtonStyle()
    }

    private var confirmationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace the Dock with \(profile.apps.count) apps?")
                .font(.headline)
            Text("The current Dock is backed up first, so you can undo this.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") {
                    showingConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Load Profile") {
                    showingConfirmation = false
                    model.applyProfile(profile, isManaged: isManaged)
                    applyCount += 1
                }
                // Deliberately the standard prominent style: this is a
                // default-action button inside a popover, not a page-level
                // CTA like the ones using prominentButtonStyle().
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// Success checkmark with bounce and the skipped-apps hint - subtle and
/// dismissible, never an alert.
private struct FeedbackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let feedback: AppModel.CleanupFeedback
    /// Changes on every apply attempt so the checkmark bounces again even
    /// when the feedback value itself is unchanged.
    let bounceTrigger: Int

    var body: some View {
        // Everything on ONE line so the footer never grows in height.
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
                // A constant trigger disarms the bounce under Reduce Motion.
                .symbolEffect(.bounce, value: reduceMotion ? 0 : bounceTrigger)
            Text("Dock updated")
                .font(.callout.weight(.medium))

            if !feedback.skipped.isEmpty {
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text("\(feedback.skipped.count) apps not installed - skipped")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(feedback.skipped.map(\.name).joined(separator: ", "))
            }

            // "?" and "×" as one tight, identically styled control pair.
            HStack(spacing: 3) {
                if !feedback.skipped.isEmpty {
                    Button {
                        model.showCleanupLog()
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show the cleanup log with details on skipped apps")
                    .accessibilityLabel("Show the cleanup log with details on skipped apps")
                }
                Button {
                    model.dismissFeedback()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .lineLimit(1)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    }
}
