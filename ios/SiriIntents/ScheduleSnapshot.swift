// ScheduleSnapshot — the read model the Siri App Intents extension answers from.
//
// The Flutter app writes this JSON into the shared App Group
// (`group.net.vogas.scheduling`, key `schedule_snapshot`) via home_widget —
// see buildScheduleSnapshot in lib/features/siri/domain/schedule_snapshot.dart.
// Keep this decoder and that builder in lockstep; they're hand-mirrored.
//
// Phases 1-3 are deliberately Firebase-free (snapshot in, speech out) for
// millisecond, offline answers — don't add a network client here without the
// Phase-4 review.
//
// This file is compiled only on macOS/Xcode (see the Mac handoff runbook).

import Foundation

private let appGroupId = "group.net.vogas.scheduling"
private let snapshotKey = "schedule_snapshot"

/// Schema version this decoder understands. A snapshot stamped with anything
/// else is rejected outright, rather than risk a mis-decode.
private let supportedVersion = 1

struct SnapshotAppointment: Codable, Hashable {
    // Non-optional on purpose: the Dart builder drops records without a doc id,
    // because a Phase-4 write action resolves its target by this id.
    let id: String
    let startMillis: Double
    let endMillis: Double
    let clientName: String
    let address: String
    let status: String

    var start: Date { Date(timeIntervalSince1970: startMillis / 1000) }
    var end: Date { Date(timeIntervalSince1970: endMillis / 1000) }

    var isDone: Bool {
        let s = status.lowercased()
        return s == "done" || s == "completed"
    }

    /// Deep link into the app's appointment detail sheet, using the scheme
    /// registered in Info.plist (`CFBundleURLTypes`) that the widget also uses.
    /// The `homeWidget` query item is required for the plugin to claim the
    /// URL — see `Job.deepLink` in ScheduleWidget.swift.
    var deepLink: URL? {
        URL(string: "esproschedule://appointment?id=\(id)&homeWidget")
    }
}

struct SnapshotDay: Codable, Hashable {
    /// Device-local calendar day, `yyyy-MM-dd`.
    let date: String
    let appointments: [SnapshotAppointment]
}

struct ScheduleSnapshot: Codable {
    let version: Int
    let generatedAt: Double
    let role: String
    let days: [SnapshotDay]

    var isAdmin: Bool { role == "admin" }

    /// The bucket for a given day, or nil when it falls outside the window the
    /// snapshot carries (today + 7).
    func day(on date: Date) -> SnapshotDay? {
        let key = ScheduleSnapshot.dayKey(date)
        return days.first { $0.date == key }
    }

    var today: SnapshotDay? { day(on: Date()) }

    /// Earliest upcoming visit across the whole window that hasn't been
    /// marked done. Cancelled visits are already excluded at build time.
    func nextAppointment(after now: Date = Date()) -> SnapshotAppointment? {
        days
            .flatMap { $0.appointments }
            .filter { $0.start > now && !$0.isDone }
            .min { $0.start < $1.start }
    }

    static func load() -> ScheduleSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let raw = defaults.string(forKey: snapshotKey),
            let data = raw.data(using: .utf8),
            let snapshot = try? JSONDecoder().decode(
                ScheduleSnapshot.self, from: data)
        else { return nil }
        guard snapshot.version == supportedVersion else { return nil }
        return snapshot
    }

    /// Matches the Dart builder's `_dayKey` — device-local, zero-padded.
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents(
            [.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
