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

  /// True for crew time blocked outside a client visit.
  final bool isPersonal;

  /// True when neither time field is required.
  final bool isAllDay;
}

class AppointmentFormValidator {
  const AppointmentFormValidator._();

  static Map<String, AppointmentFormError> validate(
    AppointmentFormInput input,
  ) {
    final errors = <String, AppointmentFormError>{};

    // Personal blocks may save under a default title.
    if (!input.isPersonal && input.title.trim().isEmpty) {
      errors['title'] = AppointmentFormError.titleRequired;
    }
    if (input.date == null) {
      errors['date'] = AppointmentFormError.dateRequired;
    }
    // All-day blocks run midnight to 23:59.
    if (!input.isAllDay && input.startTime == null) {
      errors['startTime'] = AppointmentFormError.startTimeRequired;
    }

    if (!input.isAllDay && input.endTime == null) {
      errors['endTime'] = AppointmentFormError.endTimeRequired;
    }

    // End time before start time means an overnight window.
    final date = input.date;
    final endDate = input.endDate;
    if (date != null && endDate != null) {
      // Keep reversed spans visible so validation can reject them.
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

/// The real instants an all-day run spans.
({DateTime start, DateTime end}) allDaySpan(DateTime start, DateTime end) => (
  start: start.dateOnly,
  end: DateTime(end.year, end.month, end.day, 23, 59),
);

/// Resolves form schedule fields into stored instants.
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

/// Inclusive run length for a form date pair.
int runLengthDays(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 1;
  final span = calendarDaysBetween(start, end) + 1;
  return span < 1 ? 1 : span;
}

/// True when a daily window runs past midnight.
///
/// Equal times count as a full overnight window.
bool isOvernightWindow(TimeOfDay start, TimeOfDay end) =>
    end.hour * 60 + end.minute <= start.hour * 60 + start.minute;

DateTime combineDateAndTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);

/// Returns [errors] without [key].
Map<String, AppointmentFormError> withoutKey(
  Map<String, AppointmentFormError> errors,
  String key,
) {
  if (!errors.containsKey(key)) return errors;
  return Map<String, AppointmentFormError>.from(errors)..remove(key);
}

/// [withoutKey] over several keys at once — the form setters clear a field's
/// error together with the errors of the fields it implies.
Map<String, AppointmentFormError> withoutKeys(
  Map<String, AppointmentFormError> errors,
  Iterable<String> keys,
) {
  if (!keys.any(errors.containsKey)) return errors;
  return Map<String, AppointmentFormError>.from(errors)
    ..removeWhere((k, _) => keys.contains(k));
}
