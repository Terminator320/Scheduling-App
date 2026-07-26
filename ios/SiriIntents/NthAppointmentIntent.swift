// "Read a specific appointment in ES Pro" → Siri asks "Which appointment?"
//
// Phase 3 — the multi-turn beat: an Int can't sit inside a spoken phrase
// (Siri only allows AppEnum/AppEntity there), so the phrase triggers the
// intent and Siri asks "Which appointment? Say its number," reading back
// that position — the buildable form of "read me the third one."
//
// Positions are 1-based over TODAY's list, matching the natural follow-up to
// "what's my schedule today." Answers from the App Group snapshot only — no
// network, no Firebase.
// This file is compiled only on macOS/Xcode.

import AppIntents

@available(iOS 16.0, *)
struct NthAppointmentIntent: AppIntent {
    static var title: LocalizedStringResource = "Read a specific appointment"
    static var description = IntentDescription(
        "Reads one appointment from today's schedule by its position.")

    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy =
        .alwaysAllowed

    @Parameter(
        title: "Position",
        requestValueDialog: IntentDialog(
            stringLiteral: SiriStrings.whichPositionPrompt))
    var position: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Read appointment number \(\.$position)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = ScheduleSnapshot.load() else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.noData))
        }
        let appointments = snapshot.today?.appointments ?? []
        guard position >= 1, position <= appointments.count else {
            return .result(dialog: IntentDialog(
                stringLiteral: SiriStrings.nthOutOfRange(
                    count: appointments.count, admin: snapshot.isAdmin)))
        }
        let appointment = appointments[position - 1]
        return .result(dialog: IntentDialog(
            stringLiteral: SiriStrings.nth(
                appointment, position: position, admin: snapshot.isAdmin)))
    }
}
