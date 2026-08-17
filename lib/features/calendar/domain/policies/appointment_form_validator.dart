import 'package:flutter/material.dart' show TimeOfDay;

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

enum AppointmentFormError {
  titleRequired,
  dateRequired,
  startTimeRequired,
  endTimeRequired,
  endDateBeforeStart,
  spanTooLong,
  clientRequired,
  employeesRequired,
}

class AppointmentFormInput {
  const AppointmentFormInput({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.client,
    required this.selectedEmployees,
    this.endDate,
    this.isPersonal = false,
    this.isAllDay = false,
  });

  final String title;
  final DateTime? date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final ClientRecord? client;
  final List<EmployeeRecord> selectedEmployees;

  /// The last day the crew STARTS work. Null is read as same-day.
  final DateTime? endDate;

  /// A personal job blocks time out for the crew instead of visiting a client,
  /// so it carries no client and needn't be named. Its address is optional
  /// rather than absent — the block may still have somewhere to be. The
  /// assignees are still required: they are who it is for, and who can see it.
  final bool isPersonal;

  /// No time was put in, so the block owns the whole day and neither time is
  /// required. Offered on every job, and defaulted on for an untimed personal
  /// block.
  final bool isAllDay;
}

class AppointmentFormValidator {
  const AppointmentFormValidator._();

  static Map<String, AppointmentFormError> validate(
    AppointmentFormInput input,
  ) {
    final errors = <String, AppointmentFormError>{};

    // A personal block may go unnamed — it saves under a "Personal" title.
    if (!input.isPersonal && input.title.trim().isEmpty) {
      errors['title'] = AppointmentFormError.titleRequired;
    }
    if (input.date == null) {
      errors['date'] = AppointmentFormError.dateRequired;
    }
    // An all-day block has no times to validate — it runs midnight to 23:59.
    if (!input.isAllDay && input.startTime == null) {
      errors['startTime'] = AppointmentFormError.startTimeRequired;
    }

    if (!input.isAllDay && input.endTime == null) {
      errors['endTime'] = AppointmentFormError.endTimeRequired;
    }

    // NOTE: there is deliberately no end-time-after-start-time rule. The two
    // times are a DAILY window, so an end time at or before the start time is
    // the definition of a night shift, which is supported.
    final date = input.date;
    final endDate = input.endDate;
    if (date != null && endDate != null) {
      // Raw, not clamped: this is the one caller that has to SEE an
      // out-of-range value in order to refuse it.
      final span = calendarDaysBetween(date, endDate) + 1;
      if (span < 1) {
        errors['endDate'] = AppointmentFormError.endDateBeforeStart;
      } else if (span > maxAppointmentSpanDays) {
        errors['endDate'] = AppointmentFormError.spanTooLong;
      }
    }

    if (!input.isPersonal && input.client == null) {
      errors['client'] = AppointmentFormError.clientRequired;
    }
    if (input.selectedEmployees.isEmpty) {
      errors['employees'] = AppointmentFormError.employeesRequired;
    }

    return errors;
  }
}

/// The instants an all-day run spans. Real instants, not sentinels: every
/// range query, `orderBy('startTime')` and overdue sweep in the app and on the
/// server keeps treating it as an ordinary appointment.
({DateTime start, DateTime end}) allDaySpan(DateTime start, DateTime end) => (
  start: start.dateOnly,
  end: DateTime(end.year, end.month, end.day, 23, 59),
);

/// The instants a form's schedule fields resolve to. The one place the all-day
/// convention and the overnight roll-over are chosen — both save paths route
/// through it, so the two can't drift on what gets stored.
///
/// [startTime] and [endTime] are required unless [isAllDay]; the validator has
/// already rejected an empty pair by the time a save gets here.
///
/// The times are a DAILY WINDOW. When [endTime] is at or before [startTime]
/// the window crosses midnight, so the last one finishes the morning after
/// [endDate] — which is why [endDate] always names the last day the crew
/// STARTS work, never the morning an overnight run ends.
({DateTime start, DateTime end}) appointmentSpan({
  required DateTime date,
  required DateTime endDate,
  required bool isAllDay,
  TimeOfDay? startTime,
  TimeOfDay? endTime,
}) {
  if (isAllDay) return allDaySpan(date, endDate);
  final lastDay = isOvernightWindow(startTime!, endTime!)
      ? addCalendarDays(endDate, 1)
      : endDate;
  return (
    start: combineDateAndTime(date, startTime),
    end: combineDateAndTime(lastDay, endTime),
  );
}

/// How many days a form's [start]–[end] date pair runs for, floored at 1.
///
/// The `+ 1` is the "end date names the last day the crew STARTS work" rule,
/// and it was hand-copied into both form bodies — the two of them even sharing
/// the same five-line comment, which is the tell. Lives here beside
/// [appointmentSpan], which already owns how a form's dates become instants.
///
/// A null date means the form is only half filled in, and both rows read as a
/// single-day job until it is complete; the floor covers a reversed pair,
/// which [AppointmentFormValidator] refuses separately.
int runLengthDays(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 1;
  final span = calendarDaysBetween(start, end) + 1;
  return span < 1 ? 1 : span;
}

/// True when a daily window runs past midnight.
///
/// Equal times count as overnight: a booking at the same clock time on
/// consecutive days is a run of continuous 24-hour windows, and a strict `<`
/// would collapse each of them to zero length.
bool isOvernightWindow(TimeOfDay start, TimeOfDay end) =>
    end.hour * 60 + end.minute <= start.hour * 60 + start.minute;

DateTime combineDateAndTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);

/// Returns [errors] with [key] removed, or the same map if [key] wasn't present — used to clear a field's error once the user fixes it.
Map<String, AppointmentFormError> withoutKey(
  Map<String, AppointmentFormError> errors,
  String key,
) {
  if (!errors.containsKey(key)) return errors;
  return Map<String, AppointmentFormError>.from(errors)..remove(key);
}
