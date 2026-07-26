// LiveActivitiesAppAttributes — shared ActivityKit model for the "time to
// leave" Live Activity card (Lock Screen + Dynamic Island); see
// JobLiveActivity.swift for the views and DirectionsIntent.swift for the
// Directions button.
//
// HAND-MIRRORED with functions/live_activity_utils.js `buildContentState` and
// functions/live_activity_dispatch.js `buildAttributes` — change one, change
// both.
//
// The struct name is a wire contract and MUST stay exactly
// `LiveActivitiesAppAttributes` — it must agree here, in the server's
// `ATTRIBUTES_TYPE`, and in the `live_activities` Flutter plugin's
// `Activity<LiveActivitiesAppAttributes>` registration, or push-to-start fails
// silently (no card, no error).
//
// Every display string is built server-side in EN/FR and rendered here
// verbatim — deliberately not `NSLocalizedString`, which would fork
// translations outside the ARB files.
//
// Target membership: only the ScheduleWidget extension needs this file (it
// renders the ActivityConfiguration); it does NOT belong in the Runner target
// (see LIVE_ACTIVITY_README.md).
//
// This file is compiled only on macOS/Xcode, gated to iOS 17.2+ (not 17.0 —
// `pushToStartTokenUpdates` is 17.2+, the only way this card starts).

import ActivityKit
import Foundation
import SwiftUI

// The server emits `new Date().toISOString()` (fractional seconds), which the
// default ISO8601DateFormatter (no `.withFractionalSeconds`) fails to parse —
// the same trap ScheduleWidget.swift documents.
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

struct LiveActivitiesAppAttributes: Codable, Hashable {

    /// The mutable half, replaced wholesale by every APNs update push;
    /// decodes `buildContentState`'s output key for key.
    struct ContentState: Codable, Hashable {
        /// Client name — the card headline, mirroring `AppointmentCard`.
        let clientName: String

        /// Street address. Feeds the metadata row and the Directions intent.
        let address: String

        /// ISO-8601 UTC instant for the appointment's scheduled start; null
        /// only if the server couldn't read it.
        let startTime: String?

        /// ISO-8601 UTC instant for the scheduled end; feeds the on-site
        /// remaining-time COUNTDOWN, falling back to the elapsed count-up
        /// when null (older payloads, or an unreadable record).
        let endTime: String?

        /// ISO-8601 "leave at" instant and boundary for the amber → red
        /// lapsed state; only the push that STARTS the card carries it,
        /// every later update sends null once the tech is under way.
        let leaveAt: String?

        /// Drive minutes from the sweep's one Routes API call; informational
        /// only, this card never re-polls traffic.
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
        var endDate: Date? { parseActivityInstant(endTime) }
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
            endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
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
            endTime: String? = nil,
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
            self.endTime = endTime
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

    /// Fixed for the activity's lifetime, set once at push-to-start and
    /// never re-sent in an update; feeds the "Complete" deep link.
    let appointmentId: String

    /// The assigned employee's users-doc id, as sent by `buildAttributes`.
    let employeeDocId: String

    /// The assignee's `colorValue` (ARGB32 int, see `EmployeeRecord`) driving
    /// the Lock Screen colour rail; optional only for decode safety, since a
    /// missing key on a non-optional field would fail the whole decode.
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
extension LiveActivitiesAppAttributes: ActivityAttributes {}
