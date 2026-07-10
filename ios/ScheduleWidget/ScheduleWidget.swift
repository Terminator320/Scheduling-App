// ScheduleWidget — iOS home-screen widget for the employee's schedule.
//
// Reads the JSON payload the Flutter app writes into the shared App Group
// (`group.net.vogas.scheduling`, key `schedulePayload`) via home_widget, and
// renders the "System Card" design: small = next job, medium/large = today's
// job list. The timeline advances an entry at each job's end time so "next
// job" rolls over without the app running.
//
// This file is compiled only on macOS/Xcode (see the Mac handoff runbook).

import SwiftUI
import WidgetKit

// MARK: - Payload model

private let appGroupId = "group.net.vogas.scheduling"
private let payloadKey = "schedulePayload"

struct Job: Codable, Hashable {
    let startTime: String
    let clientName: String
    let title: String
    let address: String
    let status: String

    var start: Date? {
        ISO8601DateFormatter().date(from: startTime)
    }
}

struct SchedulePayload: Codable {
    let locale: String
    let generatedAt: String
    let todayCount: Int
    let jobs: [Job]
    let nextJob: Job?

    static func load() -> SchedulePayload? {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let raw = defaults.string(forKey: payloadKey),
            let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(SchedulePayload.self, from: data)
    }
}

// MARK: - Timeline

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let payload: SchedulePayload?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), payload: nil)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ScheduleEntry) -> Void
    ) {
        completion(ScheduleEntry(date: Date(), payload: SchedulePayload.load()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ScheduleEntry>) -> Void
    ) {
        let payload = SchedulePayload.load()
        let now = Date()
        var entries = [ScheduleEntry(date: now, payload: payload)]
        // Advance an entry at each job's start so the widget dims/rolls jobs
        // off as they begin, without the app running.
        if let payload = payload {
            for job in payload.jobs {
                if let start = job.start, start > now {
                    entries.append(ScheduleEntry(date: start, payload: payload))
                }
            }
        }
        // Refresh again in an hour as a floor.
        let refresh = Calendar.current.date(
            byAdding: .hour, value: 1, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Localization helpers

private func isFrench(_ payload: SchedulePayload?) -> Bool {
    payload?.locale == "fr"
}

private func timeLabel(_ job: Job, french: Bool) -> String {
    guard let start = job.start else { return "" }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: french ? "fr_CA" : "en_CA")
    fmt.dateFormat = french ? "H 'h' mm" : "h:mm a"
    return fmt.string(from: start)
}

private func statusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "done", "completed": return .green
    case "in_progress": return Color(red: 0.0, green: 0.65, blue: 0.96)
    case "cancelled": return .red
    default: return .orange // pending
    }
}

// MARK: - Views

struct DateHeader: View {
    let french: Bool

    var body: some View {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: french ? "fr_CA" : "en_CA")
        fmt.dateFormat = french ? "EEEE d MMMM" : "EEEE, MMM d"
        return Text(fmt.string(from: Date()).uppercased())
            .font(.caption2).bold()
            .foregroundColor(.red)
            .lineLimit(1)
    }
}

struct JobRow: View {
    let job: Job
    let french: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor(job.status))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.clientName.isEmpty ? job.title : job.clientName)
                    .font(.footnote).bold()
                    .lineLimit(1)
                Text(timeLabel(job, french: french))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct SmallView: View {
    let payload: SchedulePayload?

    var body: some View {
        let french = isFrench(payload)
        return VStack(alignment: .leading, spacing: 6) {
            DateHeader(french: french)
            if let next = payload?.nextJob {
                Text(next.clientName.isEmpty ? next.title : next.clientName)
                    .font(.headline).lineLimit(1)
                Text(timeLabel(next, french: french))
                    .font(.subheadline).bold()
                    .foregroundColor(Color(red: 0.08, green: 0.4, blue: 0.75))
                    .lineLimit(1)
                if !next.address.isEmpty {
                    Text(next.address).font(.caption2)
                        .foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(remainingFooter(payload, french: french))
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            } else {
                Spacer()
                Label(
                    french ? "Aucune visite" : "No more jobs today",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.footnote).foregroundColor(.green).lineLimit(1)
                Spacer()
            }
        }
        .padding(12)
    }

    private func remainingFooter(
        _ payload: SchedulePayload?, french: Bool
    ) -> String {
        let count = payload?.todayCount ?? 0
        if french {
            return count == 1 ? "1 restante aujourd'hui"
                : "\(count) restantes aujourd'hui"
        }
        return count == 1 ? "1 left today" : "\(count) left today"
    }
}

struct ListView: View {
    let payload: SchedulePayload?
    let maxRows: Int

    var body: some View {
        let french = isFrench(payload)
        let jobs = payload?.jobs ?? []
        return VStack(alignment: .leading, spacing: 8) {
            DateHeader(french: french)
            if jobs.isEmpty {
                Spacer()
                Label(
                    french ? "Aucune visite aujourd'hui"
                        : "No jobs today",
                    systemImage: "checkmark.circle.fill"
                ).font(.footnote).foregroundColor(.green).lineLimit(1)
                Spacer()
            } else {
                ForEach(jobs.prefix(maxRows), id: \.self) { job in
                    JobRow(job: job, french: french)
                }
                if jobs.count > maxRows {
                    Text(moreLabel(jobs.count - maxRows, french: french))
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }

    private func moreLabel(_ n: Int, french: Bool) -> String {
        french ? "+\(n) autres aujourd'hui" : "+\(n) more today"
    }
}

struct ScheduleWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(payload: entry.payload)
        case .systemLarge:
            ListView(payload: entry.payload, maxRows: 6)
        default:
            ListView(payload: entry.payload, maxRows: 3)
        }
    }
}

// MARK: - Widget

@main
struct ScheduleWidget: Widget {
    let kind = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Schedule")
        .description("Your next job and today's schedule.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
