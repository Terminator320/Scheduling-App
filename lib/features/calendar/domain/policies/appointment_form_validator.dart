import 'package:flutter/material.dart' show TimeOfDay;

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

enum AppointmentFormError {
  titleRequired,
  dateRequired,
  startTimeRequired,
  endTimeRequired,
  endTimeMustBeAfterStart,
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
    this.isPersonal = false,
    this.isAllDay = false,
  });

  final String title;
  final DateTime? date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final ClientRecord? client;
  final List<EmployeeRecord> selectedEmployees;

  /// A personal job blocks time out for the crew instead of visiting a client,
  /// so it carries no client, no address, and needn't be named. The assignees
  /// are still required — they are who the block is for, and who can see it.
  final bool isPersonal;

  /// No time was put in, so the block owns the whole day and neither time is
  /// required. Only reachable on a personal job.
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
    } else if (!input.isAllDay &&
        input.endTime != null &&
        input.date != null &&
        input.startTime != null) {
      // The `!isAllDay` guard is load-bearing: times picked BEFORE all-day was
      // switched on stay in state, so without it a stale equal start/end
      // re-raises endTimeMustBeAfterStart against rows that are no longer on
      // screen — Save then fails with nothing to fix.
      final start = combineDateAndTime(input.date!, input.startTime!);
      final end = combineEndDateAndTime(
        input.date!,
        input.endTime!,
        input.startTime,
      );
      if (!end.isAfter(start)) {
        errors['endTime'] = AppointmentFormError.endTimeMustBeAfterStart;
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

/// The instants an all-day block spans. Real instants, not sentinels: every
/// range query, `orderBy('startTime')` and overdue sweep in the app and on the
/// server keeps treating it as an ordinary appointment.
({DateTime start, DateTime end}) allDaySpan(DateTime date) => (
  start: date.dateOnly,
  end: DateTime(date.year, date.month, date.day, 23, 59),
);

/// The instants a form's schedule fields resolve to. The one place the
/// all-day convention is chosen over picked times — both save paths route
/// through it, so the two can't drift on what "all day" stores.
///
/// [startTime] and [endTime] are required unless [isAllDay]; the validator has
/// already rejected an empty pair by the time a save gets here.
({DateTime start, DateTime end}) appointmentSpan({
  required DateTime date,
  required bool isAllDay,
  TimeOfDay? startTime,
  TimeOfDay? endTime,
}) {
  if (isAllDay) return allDaySpan(date);
  return (
    start: combineDateAndTime(date, startTime!),
    end: combineEndDateAndTime(date, endTime!, startTime),
  );
}

DateTime combineDateAndTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);

DateTime combineEndDateAndTime(
  DateTime date,
  TimeOfDay endTime, [
  TimeOfDay? startTime,
]) {
  final end = combineDateAndTime(date, endTime);
  if (startTime == null) return end;
  final start = combineDateAndTime(date, startTime);
  // Only bump to the next day when the end is strictly before the start — that's an overnight job. If the end equals the start, we leave it same-day so the validator rejects it instead of silently booking a ~24h appointment.
  return end.isBefore(start)
      ? DateTime(
          date.year,
          date.month,
          date.day + 1,
          endTime.hour,
          endTime.minute,
        )
      : end;
}

/// Returns [errors] with [key] removed, or the same map if [key] wasn't present — used to clear a field's error once the user fixes it.
Map<String, AppointmentFormError> withoutKey(
  Map<String, AppointmentFormError> errors,
  String key,
) {
  if (!errors.containsKey(key)) return errors;
  return Map<String, AppointmentFormError>.from(errors)..remove(key);
}
