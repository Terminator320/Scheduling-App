// SiriStrings — spoken response text in English and French.
//
// The response language follows the device's Siri language (`Locale.current`),
// matching how ScheduleWidget.swift picks its labels. Kept as plain Swift
// rather than a string catalog so the two localizations stay side by side and
// reviewable in one place.
//
// This file is compiled only on macOS/Xcode.

import Foundation

enum SiriStrings {
    static var french: Bool {
        Locale.current.identifier.hasPrefix("fr")
    }

    // MARK: - Time formatting

    static func time(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: french ? "fr_CA" : "en_CA")
        fmt.dateFormat = french ? "H 'h' mm" : "h:mm a"
        return fmt.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: french ? "fr_CA" : "en_CA")
        fmt.dateFormat = french ? "EEEE d MMMM" : "EEEE, MMMM d"
        return fmt.string(from: date)
    }

    /// How to name a day in a spoken sentence: "today"/"tomorrow" read more
    /// naturally than a full weekday, so prefer them; otherwise fall back to the
    /// weekday-and-date form. Used by the Phase-2 day-schedule answers.
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return french ? "aujourd'hui" : "today"
        }
        if cal.isDateInTomorrow(date) {
            return french ? "demain" : "tomorrow"
        }
        // "on Friday, July 25" / "vendredi 25 juillet" — French takes no "on".
        return french ? weekday(date) : "on \(weekday(date))"
    }

    // MARK: - Shared states

    /// No snapshot in the App Group: signed out, or the app has never run.
    static var noData: String {
        french
            ? "Ouvrez ES Pro pour synchroniser votre horaire."
            : "Open ES Pro to sync your schedule."
    }

    // MARK: - Count

    static func count(_ n: Int, admin: Bool) -> String {
        if french {
            let scope = admin ? "L'équipe a" : "Vous avez"
            if n == 0 {
                return admin
                    ? "L'équipe n'a aucun rendez-vous aujourd'hui."
                    : "Vous n'avez aucun rendez-vous aujourd'hui."
            }
            return n == 1
                ? "\(scope) 1 rendez-vous aujourd'hui."
                : "\(scope) \(n) rendez-vous aujourd'hui."
        }
        let scope = admin ? "The team has" : "You have"
        if n == 0 {
            return admin
                ? "The team has no appointments today."
                : "You have no appointments today."
        }
        return n == 1
            ? "\(scope) 1 appointment today."
            : "\(scope) \(n) appointments today."
    }

    // MARK: - Day schedule

    static func emptyDay(admin: Bool) -> String {
        if french {
            return admin
                ? "Aucun rendez-vous pour l'équipe aujourd'hui."
                : "Vous n'avez aucun rendez-vous aujourd'hui."
        }
        return admin
            ? "No appointments for the team today."
            : "You have no appointments today."
    }

    static func scheduleIntro(_ n: Int, admin: Bool) -> String {
        if french {
            let scope = admin ? "L'équipe a" : "Vous avez"
            return n == 1
                ? "\(scope) 1 rendez-vous aujourd'hui :"
                : "\(scope) \(n) rendez-vous aujourd'hui :"
        }
        let scope = admin ? "The team has" : "You have"
        return n == 1
            ? "\(scope) 1 appointment today:"
            : "\(scope) \(n) appointments today:"
    }

    /// One spoken line per visit — time plus who it's for.
    static func scheduleLine(_ appointment: SnapshotAppointment) -> String {
        let at = time(appointment.start)
        let who = appointment.clientName.isEmpty
            ? (french ? "client sans nom" : "unnamed client")
            : appointment.clientName
        return "\(at), \(who)"
    }

    // MARK: - Day schedule (Phase 2 — specific day)

    /// Siri asks this when a day-schedule request arrives with no spoken date.
    static var whichDayPrompt: String {
        french ? "Pour quel jour ?" : "For what day?"
    }

    /// The requested day is past or beyond the 7-day snapshot window.
    static var outOfWindow: String {
        french
            ? "Je n'ai votre horaire que pour les 7 prochains jours."
            : "I only have your schedule for the next 7 days."
    }

    static func emptyDayFor(_ date: Date, admin: Bool) -> String {
        let when = relativeDay(date)
        if french {
            return admin
                ? "Aucun rendez-vous pour l'équipe \(when)."
                : "Vous n'avez aucun rendez-vous \(when)."
        }
        return admin
            ? "No appointments for the team \(when)."
            : "You have no appointments \(when)."
    }

    static func scheduleIntroFor(
        _ n: Int, date: Date, admin: Bool
    ) -> String {
        let when = relativeDay(date)
        if french {
            let scope = admin ? "L'équipe a" : "Vous avez"
            return n == 1
                ? "\(scope) 1 rendez-vous \(when) :"
                : "\(scope) \(n) rendez-vous \(when) :"
        }
        let scope = admin ? "The team has" : "You have"
        return n == 1
            ? "\(scope) 1 appointment \(when):"
            : "\(scope) \(n) appointments \(when):"
    }

    // MARK: - Next appointment

    static var noNext: String {
        french
            ? "Aucun rendez-vous à venir dans les 7 prochains jours."
            : "No upcoming appointments in the next 7 days."
    }

    static func next(_ appointment: SnapshotAppointment) -> String {
        let who = appointment.clientName.isEmpty
            ? (french ? "un client sans nom" : "an unnamed client")
            : appointment.clientName
        let sameDay = Calendar.current.isDateInToday(appointment.start)
        let when = sameDay
            ? (french
                ? "aujourd'hui à \(time(appointment.start))"
                : "today at \(time(appointment.start))")
            : (french
                ? "\(weekday(appointment.start)) à \(time(appointment.start))"
                : "\(weekday(appointment.start)) at \(time(appointment.start))")
        var line = french
            ? "Votre prochain rendez-vous est \(when) avec \(who)."
            : "Your next appointment is \(when) with \(who)."
        if !appointment.address.isEmpty {
            line += french
                ? " Adresse : \(appointment.address)."
                : " Address: \(appointment.address)."
        }
        return line
    }

    // MARK: - Nth appointment (Phase 3 — parameter follow-up)

    /// Siri's follow-up when "read a specific appointment" arrives with no
    /// number — the multi-turn beat: Siri asks, the caller answers in-session.
    static var whichPositionPrompt: String {
        french
            ? "Quel rendez-vous ? Dites son numéro."
            : "Which appointment? Say its number."
    }

    // Ordinal words 1-10; beyond that the sentence falls back to "number N" /
    // "numéro N" (a day rarely has more than ten visits, and the cap is 30).
    private static let ordinalsEn = [
        "first", "second", "third", "fourth", "fifth",
        "sixth", "seventh", "eighth", "ninth", "tenth",
    ]
    private static let ordinalsFr = [
        "premier", "deuxième", "troisième", "quatrième", "cinquième",
        "sixième", "septième", "huitième", "neuvième", "dixième",
    ]

    /// The asked-for position is past the end of today's list (or the day is
    /// empty — reuses the plain "no appointments today").
    static func nthOutOfRange(count: Int, admin: Bool) -> String {
        if count == 0 { return emptyDay(admin: admin) }
        if french {
            let scope = admin ? "L'équipe n'a que" : "Vous n'avez que"
            return count == 1
                ? (admin
                    ? "L'équipe n'a qu'un seul rendez-vous aujourd'hui."
                    : "Vous n'avez qu'un seul rendez-vous aujourd'hui.")
                : "\(scope) \(count) rendez-vous aujourd'hui."
        }
        let scope = admin ? "The team only has" : "You only have"
        return count == 1
            ? "\(scope) 1 appointment today."
            : "\(scope) \(count) appointments today."
    }

    /// Reads one visit named by its 1-based position in today's list.
    static func nth(
        _ appointment: SnapshotAppointment, position: Int, admin: Bool
    ) -> String {
        let at = time(appointment.start)
        let who = appointment.clientName.isEmpty
            ? (french ? "un client sans nom" : "an unnamed client")
            : appointment.clientName
        let idx = position - 1
        var line: String
        if french {
            let subject: String
            if idx >= 0 && idx < ordinalsFr.count {
                let ord = ordinalsFr[idx]
                subject = admin
                    ? "Le \(ord) rendez-vous de l'équipe"
                    : "Votre \(ord) rendez-vous"
            } else {
                subject = admin
                    ? "Le rendez-vous numéro \(position) de l'équipe"
                    : "Votre rendez-vous numéro \(position)"
            }
            line = "\(subject) aujourd'hui est à \(at) avec \(who)."
            if !appointment.address.isEmpty {
                line += " Adresse : \(appointment.address)."
            }
        } else {
            let subject: String
            if idx >= 0 && idx < ordinalsEn.count {
                let ord = ordinalsEn[idx]
                subject = admin
                    ? "The team's \(ord) appointment"
                    : "Your \(ord) appointment"
            } else {
                subject = admin
                    ? "The team's appointment number \(position)"
                    : "Your appointment number \(position)"
            }
            line = "\(subject) today is at \(at) with \(who)."
            if !appointment.address.isEmpty {
                line += " Address: \(appointment.address)."
            }
        }
        return line
    }
}
