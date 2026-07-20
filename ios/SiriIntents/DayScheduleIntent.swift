// "Read my schedule for a day in ES Pro" → Siri asks "For what day?"
//
// Reads an arbitrary day's bucket out loud. The snapshot already carries today
// through +7 days, so this is a pure projection over that data — no schema
// change from the Phase-1 read intents. ("Today" and "tomorrow" have their own
// deterministic intents; this covers weekdays and dates further out.)
//
// A `Date` parameter cannot be interpolated into a spoken App Shortcut phrase
// (Siri only allows AppEnum/AppEntity parameters there), so the phrase triggers
// the intent and Siri resolves `targetDate` via its own locale-aware date
// prompt — "Friday"/"vendredi"/"July 25" all parse without a string catalog.
// We map the resolved date to a `days[]` bucket by its local calendar day; a
// date outside the 8-day window (past, or > 7 days out) has no bucket and is
// answered "I only have your schedule for the next 7 days."
//
// Answers from the App Group snapshot only — no network, no Firebase.
// This file is compiled only on macOS/Xcode.

import AppIntents

@available(iOS 16.0, *)
struct DayScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Schedule for a day"
    static var description = IntentDescription(
        "Reads out the appointments for a given day.")

    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy =
        .alwaysAllowed

    @Parameter(
        title: "Day",
        requestValueDialog: IntentDialog(
            stringLiteral: SiriStrings.whichDayPrompt))
    var targetDate: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Read the schedule for \(\.$targetDate)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = ScheduleSnapshot.load() else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.noData))
        }
        // No bucket for this day → it falls outside the today…+7 window the
        // snapshot carries (or it's in the past).
        guard let bucket = snapshot.day(on: targetDate) else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.outOfWindow))
        }
        let appointments = bucket.appointments
        guard !appointments.isEmpty else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.emptyDayFor(
                    targetDate, admin: snapshot.isAdmin)))
        }
        let intro = SiriStrings.scheduleIntroFor(
            appointments.count, date: targetDate, admin: snapshot.isAdmin)
        let lines = appointments.map(SiriStrings.scheduleLine)
        let spoken = ([intro] + lines).joined(separator: " ")
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}
