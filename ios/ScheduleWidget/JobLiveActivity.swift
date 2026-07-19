// JobLiveActivity — the "time to leave" Live Activity: Lock Screen card plus
// Dynamic Island. Started, updated, and ended entirely by the server over
// direct APNs (FCM cannot send `apns-push-type: liveactivity`); nothing here
// talks to Firebase or the network.
//
// Visual direction is "Option B — job-card continuity" (see
// docs/plans/2026-07-19-ios-live-activities.md): employee colour rail, client
// as the headline, status chip, metadata row — the same shape as
// AppointmentCard, so staff read a layout they already know all day.
//
// Every display string comes from the content state, which the server builds
// in EN/FR. Never NSLocalizedString here — translations live in the ARBs.
//
// Gated to iOS 17.2 (not 17.0): `pushToStartTokenUpdates` is 17.2+, and
// push-to-start is the only way this card ever starts. Devices below that see
// no card and behave exactly as they do today.
//
// This file is compiled only on macOS/Xcode (see LIVE_ACTIVITY_README.md).

import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Palette

private let amber = Color.orange
private let lapsedRed = Color.red
private let onSiteGreen = Color(red: 0.13, green: 0.65, blue: 0.35)

@available(iOS 16.1, *)
private func phaseAccent(
    for state: LiveActivitiesAppAttributes.ContentState, now: Date
) -> Color {
    if state.isOnSite { return onSiteGreen }
    return state.isLapsed(at: now) ? lapsedRed : amber
}

// MARK: - Compact Island text

/// "Leave at 7:54" -> "Leave at". Splitting the server string keeps the
/// compact Island bilingual without a second translation table.
private func labelPart(_ text: String) -> String {
    guard let digit = text.firstIndex(where: { $0.isNumber }) else {
        return text
    }
    return String(text[text.startIndex..<digit])
        .trimmingCharacters(in: .whitespaces)
}

/// "Leave at 7:54" -> "7:54".
private func timePart(_ text: String) -> String {
    guard let digit = text.firstIndex(where: { $0.isNumber }) else {
        return text
    }
    return String(text[digit...]).trimmingCharacters(in: .whitespaces)
}

// MARK: - Pieces

@available(iOS 16.1, *)
private struct StatusChip: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption2).bold()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.22), in: Capsule())
            .foregroundColor(tint)
    }
}

@available(iOS 16.1, *)
private struct PillLabel: View {
    let text: String
    let systemImage: String
    let tint: Color
    let filled: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption).bold()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(filled ? tint : Color.clear, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    filled ? Color.clear : tint.opacity(0.75), lineWidth: 1))
            .foregroundColor(filled ? .white : tint)
    }
}

/// The ES mark, falling back to an SF Symbol when the asset catalog has no
/// `BrandMark` image set (see LIVE_ACTIVITY_README.md).
private struct BrandGlyph: View {
    var body: some View {
        if let image = UIImage(named: "BrandMark") {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "wrench.and.screwdriver.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - Lock Screen card

@available(iOS 17.2, *)
private struct LockScreenCard: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>

    private var state: LiveActivitiesAppAttributes.ContentState {
        context.state
    }

    var body: some View {
        // Read once per render: the amber -> red lapse repaints when the next
        // update push lands, which the 5-minute sweep already provides.
        let now = Date()
        let tint = phaseAccent(for: state, now: now)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(context.attributes.railColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                header(tint: tint)
                metadata
                buttons(tint: tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .widgetURL(context.attributes.deepLink)
    }

    private func header(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(state.clientName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusChip(label: state.statusLabel, tint: tint)
            }
            if state.isOnSite, let start = state.startDate {
                Text(timerInterval: start...Date.distantFuture,
                     countsDown: false)
                    .font(.title3).bold()
                    .monospacedDigit()
                    .foregroundColor(tint)
                    .lineLimit(1)
            } else if !state.timeLabel.isEmpty {
                Text(state.timeLabel)
                    .font(.title3).bold()
                    .foregroundColor(tint)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        let parts = [state.address, state.driveLabel]
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    // Travel: Directions leads (the lock-screen win). On site: Complete leads
    // — the order matches what the tech would actually tap next.
    private func buttons(tint: Color) -> some View {
        HStack(spacing: 8) {
            if state.isOnSite {
                completeButton(filled: true, tint: tint)
                directionsButton(filled: false, tint: tint)
            } else {
                directionsButton(filled: true, tint: tint)
                completeButton(filled: false, tint: tint)
            }
        }
    }

    @ViewBuilder
    private func directionsButton(filled: Bool, tint: Color) -> some View {
        if state.address.isEmpty {
            EmptyView()
        } else {
            Button(intent: DirectionsIntent(address: state.address)) {
                PillLabel(
                    text: state.directionsLabel,
                    systemImage: "location.fill",
                    tint: tint,
                    filled: filled)
            }
            .buttonStyle(.plain)
        }
    }

    // "Complete" deep-links into the appointment sheet, where the existing
    // markAsDone path runs with real Auth + App Check — the extension never
    // becomes an authenticated write surface.
    @ViewBuilder
    private func completeButton(filled: Bool, tint: Color) -> some View {
        if let url = context.attributes.deepLink {
            Link(destination: url) {
                PillLabel(
                    text: state.completeLabel,
                    systemImage: "checkmark.circle.fill",
                    tint: filled ? onSiteGreen : tint,
                    filled: filled)
            }
        }
    }
}

// MARK: - Widget

@available(iOS 17.2, *)
struct JobLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            LockScreenCard(context: context)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            let tint = phaseAccent(for: state, now: Date())
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // Leads on an ABSOLUTE time ("Leave at 7:54"), never a
                    // countdown: a countdown frozen by a delayed push or a
                    // sleeping device is actively misleading, while an
                    // absolute time is still correct on wake.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.timeLabel)
                            .font(.headline)
                            .foregroundColor(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(state.clientName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusChip(label: state.statusLabel, tint: tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        let parts = [state.address, state.driveLabel]
                            .filter { !$0.isEmpty }
                        if !parts.isEmpty {
                            Text(parts.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            if !state.address.isEmpty {
                                Button(intent: DirectionsIntent(
                                    address: state.address)) {
                                    PillLabel(
                                        text: state.directionsLabel,
                                        systemImage: "location.fill",
                                        tint: tint,
                                        filled: !state.isOnSite)
                                }
                                .buttonStyle(.plain)
                            }
                            if let url = context.attributes.deepLink {
                                Link(destination: url) {
                                    PillLabel(
                                        text: state.completeLabel,
                                        systemImage: "checkmark.circle.fill",
                                        tint: state.isOnSite
                                            ? onSiteGreen : tint,
                                        filled: state.isOnSite)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                Text(labelPart(state.timeLabel))
                    .font(.caption2)
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } compactTrailing: {
                Text(timePart(state.timeLabel))
                    .font(.caption2).bold()
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                // ~46 pt shared with other apps — a time will not fit legibly,
                // so the tinted mark carries the "act soon" signal alone.
                BrandGlyph()
                    .foregroundColor(tint)
                    .padding(2)
            }
            .widgetURL(context.attributes.deepLink)
            .keylineTint(tint)
        }
    }
}
