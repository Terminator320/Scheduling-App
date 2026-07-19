// "How many appointments do I have today in ES Pro?"
//
// Answers from the App Group snapshot only — no network, no Firebase.
// This file is compiled only on macOS/Xcode.

import AppIntents

@available(iOS 16.0, *)
struct AppointmentCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Appointment count today"
    static var description = IntentDescription(
        "Says how many appointments are on today's schedule.")

    // Reads are safe from the lock screen: it's the caller's own schedule, and
    // the hands-free case (driving between jobs) is the point. Write intents
    // (Phase 4) must NOT set this.
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy =
        .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = ScheduleSnapshot.load() else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.noData))
        }
        let count = snapshot.today?.appointments.count ?? 0
        return .result(dialog: IntentDialog(
            stringLiteral: SiriStrings.count(count, admin: snapshot.isAdmin)))
    }
}
