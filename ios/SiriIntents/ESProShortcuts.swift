// ESProShortcuts — the spoken phrases Siri recognizes, with no user setup.
//
// Apple requires the app name in every phrase; `\(.applicationName)` resolves
// to the app's name (and its alternate names, if declared in
// `AppShortcuts.strings`). Both English and French phrases are listed here —
// Siri matches whichever language the device is set to.
//
// This file is compiled only on macOS/Xcode.

import AppIntents

@available(iOS 16.0, *)
struct ESProShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppointmentCountIntent(),
            phrases: [
                "How many appointments do I have today in \(.applicationName)",
                "How many jobs do I have today in \(.applicationName)",
                "Combien de rendez-vous ai-je aujourd'hui dans \(.applicationName)",
                "Combien de visites ai-je aujourd'hui dans \(.applicationName)",
            ],
            shortTitle: "Appointment count",
            systemImageName: "number.circle")

        AppShortcut(
            intent: TodayScheduleIntent(),
            phrases: [
                "What's my schedule today in \(.applicationName)",
                "What's on my schedule in \(.applicationName)",
                "Read my schedule in \(.applicationName)",
                "Quel est mon horaire aujourd'hui dans \(.applicationName)",
                "Lis mon horaire dans \(.applicationName)",
            ],
            shortTitle: "Today's schedule",
            systemImageName: "calendar")

        AppShortcut(
            intent: NextAppointmentIntent(),
            phrases: [
                "What's my next appointment in \(.applicationName)",
                "What's my next job in \(.applicationName)",
                "Where am I going next in \(.applicationName)",
                "Quel est mon prochain rendez-vous dans \(.applicationName)",
                "Où est ma prochaine visite dans \(.applicationName)",
            ],
            shortTitle: "Next appointment",
            systemImageName: "arrow.right.circle")

        // "Tomorrow" is by far the most common relative-day query, so it gets
        // its own deterministic intent (no parameter) — single-utterance in
        // both languages, and zero App Intents ambiguity.
        AppShortcut(
            intent: TomorrowScheduleIntent(),
            phrases: [
                "What's my schedule tomorrow in \(.applicationName)",
                "What's on my schedule tomorrow in \(.applicationName)",
                "Read my schedule for tomorrow in \(.applicationName)",
                "Quel est mon horaire demain dans \(.applicationName)",
                "Lis mon horaire de demain dans \(.applicationName)",
            ],
            shortTitle: "Tomorrow's schedule",
            systemImageName: "calendar.badge.clock")

        // Any other day. A `Date` parameter can't be interpolated into a
        // spoken phrase (Siri only allows AppEnum/AppEntity parameters there),
        // so the phrase triggers the intent and Siri then asks "For what day?"
        // and parses the spoken date — locale-aware, so "Friday"/"vendredi"
        // and "July 25" both resolve without a string catalog.
        AppShortcut(
            intent: DayScheduleIntent(),
            phrases: [
                "Read my schedule for a day in \(.applicationName)",
                "What's my schedule for a specific day in \(.applicationName)",
                "Look up my schedule for a day in \(.applicationName)",
                "Consulte mon horaire pour un jour dans \(.applicationName)",
                "Quel est mon horaire pour un jour dans \(.applicationName)",
            ],
            shortTitle: "Schedule for a day",
            systemImageName: "calendar")

        // Phase 3 — parameter follow-up. The position can't sit in the phrase
        // (Int isn't an allowed phrase parameter), so the phrase triggers the
        // intent and Siri asks "Which appointment? Say its number" — the
        // multi-turn beat, in-session.
        AppShortcut(
            intent: NthAppointmentIntent(),
            phrases: [
                "Read a specific appointment in \(.applicationName)",
                "Read one of my appointments in \(.applicationName)",
                "Read an appointment from my schedule in \(.applicationName)",
                "Lis un rendez-vous précis dans \(.applicationName)",
                "Lis un de mes rendez-vous dans \(.applicationName)",
            ],
            shortTitle: "Read a specific appointment",
            systemImageName: "list.number")
    }
}
