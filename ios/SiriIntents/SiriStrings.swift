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
}
