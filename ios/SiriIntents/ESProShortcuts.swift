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
    }
}
