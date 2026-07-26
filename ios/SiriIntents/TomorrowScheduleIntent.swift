// "What's my schedule tomorrow in ES Pro?"
//
// Reads tomorrow's bucket out loud (time + client name per visit);
// deterministic (no parameter) for a single-utterance match in both
// languages, mirroring TodayScheduleIntent with only the target day different.
//
// Answers from the App Group snapshot only — no network, no Firebase.
// This file is compiled only on macOS/Xcode.

import AppIntents

@available(iOS 16.0, *)
struct TomorrowScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Tomorrow's schedule"
    static var description = IntentDescription(
        "Reads out tomorrow's appointments.")

    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy =
        .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = ScheduleSnapshot.load() else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.noData))
        }
        let tomorrow = Calendar.current.date(
            byAdding: .day, value: 1, to: Date()) ?? Date()
        let appointments = snapshot.day(on: tomorrow)?.appointments ?? []
        guard !appointments.isEmpty else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.emptyDayFor(
                    tomorrow, admin: snapshot.isAdmin)))
        }
        let intro = SiriStrings.scheduleIntroFor(
            appointments.count, date: tomorrow, admin: snapshot.isAdmin)
        let lines = appointments.map(SiriStrings.scheduleLine)
        let spoken = ([intro] + lines).joined(separator: " ")
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}
