// JobActivityAttributes — shared ActivityKit model for the "time to leave"
// Live Activity card (Lock Screen + Dynamic Island). See JobLiveActivity.swift
// for the views and DirectionsIntent.swift for the Directions button.
//
// HAND-MIRRORED with functions/live_activity_utils.js `buildContentState` and
// functions/live_activity_dispatch.js `buildAttributes` — change one, change
// both. The struct NAME is itself a wire contract: the server sends it as the
// push envelope's `attributes-type` (`ATTRIBUTES_TYPE`), so renaming this type
// makes every push-to-start fail silently.
//
// Every display string is built server-side in EN/FR (from the same table
// shape as the notification bodies, keyed off the per-token `locale`) and
// rendered here verbatim. Deliberately NOT `NSLocalizedString`: that would
// fork translations into a second system outside the ARB files, invisible to
// `untranslated.json`.
//
// IMPORTANT: this type must be in Target Membership for BOTH the Runner app
// target (which observes `pushToStartTokenUpdates` / `activityUpdates` to
// register tokens — see `lib/features/live_activity/`) and the ScheduleWidget
// extension target (which renders the ActivityConfiguration). New files under
// ios/ScheduleWidget/ are picked up automatically by the
// PBXFileSystemSynchronizedRootGroup, but that auto-sync wires a file into the
// EXTENSION target only — adding this one file to Runner as well is a manual
// "Target Membership" checkbox in Xcode's File Inspector. See
// LIVE_ACTIVITY_README.md.
//
// This file is compiled only on macOS/Xcode. The `ActivityAttributes`
// conformance is `@available(iOS 16.1, *)` so the file still compiles at the
// project's iOS 15.0 deployment target; the widget and every registration path
// are gated to 17.2+ (not 17.0 — `pushToStartTokenUpdates` is 17.2+, and
// push-to-start is the only way this card starts).

import ActivityKit
import Foundation
import SwiftUI

// The server emits `new Date().toISOString()`, which HAS fractional seconds. A
// default ISO8601DateFormatter has no `.withFractionalSeconds` and returns nil
// for that string — the same trap ScheduleWidget.swift documents.
private let activityIsoWithMillis: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let activityIsoNoMillis = ISO8601DateFormatter()

private func parseActivityInstant(_ raw: String?) -> Date? {
    guard let raw = raw, !raw.isEmpty else { return nil }
    return activityIsoWithMillis.date(from: raw)
        ?? activityIsoNoMillis.date(from: raw)
}

struct JobActivityAttributes: Codable, Hashable {

    /// The mutable half — replaced wholesale by every APNs update push.
    /// Decodes `buildContentState`'s output key for key.
    struct ContentState: Codable, Hashable {
        /// Client name — the card headline, mirroring `AppointmentCard`.
        let clientName: String

        /// Street address. Feeds the metadata row and the Directions intent.
        let address: String

        /// ISO-8601 UTC instant for the appointment's scheduled start. Null
        /// only if the server could not read it.
        let startTime: String?

        /// ISO-8601 UTC instant for the absolute "leave at" time. Null when
        /// the sweep fell back to the fixed 30-minute reminder. Also the
        /// boundary for the amber → red lapsed state.
        let leaveAt: String?

        /// Drive minutes from the one Routes API call the sweep already makes.
        /// Informational — this card never re-polls traffic.
        let travelMinutes: Int?

        /// "travel" | "onSite", clock-derived server-side by `phaseFor`.
        let phase: String

        // Pre-localized display strings. Rendered verbatim.
        let statusLabel: String
        let timeLabel: String
        let driveLabel: String
        let directionsLabel: String
        let completeLabel: String

        var startDate: Date? { parseActivityInstant(startTime) }
        var leaveAtDate: Date? { parseActivityInstant(leaveAt) }

        var isOnSite: Bool { phase == "onSite" }

        /// True once the departure time has passed while still travelling —
        /// the lapsed state the card paints red (with no text change).
        func isLapsed(at now: Date) -> Bool {
            guard !isOnSite, let leave = leaveAtDate else { return false }
            return now >= leave
        }

        // Decoded field by field with defaults so one added or renamed server
        // key can't fail the whole decode and drop the card entirely.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clientName =
                try c.decodeIfPresent(String.self, forKey: .clientName) ?? ""
            address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
            startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
            leaveAt = try c.decodeIfPresent(String.self, forKey: .leaveAt)
            travelMinutes =
                try c.decodeIfPresent(Int.self, forKey: .travelMinutes)
            phase =
                try c.decodeIfPresent(String.self, forKey: .phase) ?? "travel"
            statusLabel =
                try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
            timeLabel =
                try c.decodeIfPresent(String.self, forKey: .timeLabel) ?? ""
            driveLabel =
                try c.decodeIfPresent(String.self, forKey: .driveLabel) ?? ""
            directionsLabel =
                try c.decodeIfPresent(
                    String.self, forKey: .directionsLabel) ?? ""
            completeLabel =
                try c.decodeIfPresent(String.self, forKey: .completeLabel) ?? ""
        }

        init(
            clientName: String,
            address: String,
            startTime: String?,
            leaveAt: String?,
            travelMinutes: Int?,
            phase: String,
            statusLabel: String,
            timeLabel: String,
            driveLabel: String,
            directionsLabel: String,
            completeLabel: String
        ) {
            self.clientName = clientName
            self.address = address
            self.startTime = startTime
            self.leaveAt = leaveAt
            self.travelMinutes = travelMinutes
            self.phase = phase
            self.statusLabel = statusLabel
            self.timeLabel = timeLabel
            self.driveLabel = driveLabel
            self.directionsLabel = directionsLabel
            self.completeLabel = completeLabel
        }
    }

    /// Fixed for the activity's lifetime — set once at push-to-start from
    /// `buildAttributes`, never re-sent in an update. Feeds the "Complete"
    /// deep link.
    let appointmentId: String

    /// The assigned employee's users-doc id, as sent by `buildAttributes`.
    let employeeDocId: String

    /// The assignee's `colorValue` (ARGB32 int, see `EmployeeRecord`) driving
    /// the Lock Screen colour rail. Optional because `buildAttributes` does
    /// not send it yet — a missing key on a non-optional field would fail the
    /// whole push-to-start decode and drop the card.
    let employeeColorValue: Int?

    init(
        appointmentId: String,
        employeeDocId: String = "",
        employeeColorValue: Int? = nil
    ) {
        self.appointmentId = appointmentId
        self.employeeDocId = employeeDocId
        self.employeeColorValue = employeeColorValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appointmentId =
            try c.decodeIfPresent(String.self, forKey: .appointmentId) ?? ""
        employeeDocId =
            try c.decodeIfPresent(String.self, forKey: .employeeDocId) ?? ""
        employeeColorValue =
            try c.decodeIfPresent(Int.self, forKey: .employeeColorValue)
    }

    /// Deep link into the app's appointment detail sheet — the same scheme the
    /// home-screen widget uses (`CFBundleURLTypes` in Runner/Info.plist).
    var deepLink: URL? {
        guard !appointmentId.isEmpty else { return nil }
        return URL(string: "esproschedule://appointment?id=\(appointmentId)")
    }

    /// The employee colour rail, falling back to the card's amber accent when
    /// no colour was sent.
    var railColor: Color {
        guard let value = employeeColorValue, value != 0 else { return .orange }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

@available(iOS 16.1, *)
extension JobActivityAttributes: ActivityAttributes {}
