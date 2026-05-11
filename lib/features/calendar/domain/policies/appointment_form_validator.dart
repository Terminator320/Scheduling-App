import 'package:flutter/material.dart' show TimeOfDay;

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Validation error keys produced by `AppointmentFormValidator`. The widget
/// layer maps each enum value to a localized string via `context.l10n.*` —
/// keeping the validator pure-Dart and l10n-free.
enum AppointmentFormError {
  titleRequired,
  dateRequired,
  startTimeRequired,
  endTimeRequired,
  endTimeMustBeAfterStart,
  clientRequired,
  employeesRequired,
}

/// Bag of values pulled out of the form for validation. Optional fields
/// are nullable so the validator can report "please pick a date" vs
/// "please pick a start time" independently.
class AppointmentFormInput {
  const AppointmentFormInput({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.client,
    required this.selectedEmployees,
  });

  final String title;
  final DateTime? date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final ClientRecord? client;
  final List<EmployeeRecord> selectedEmployees;
}

/// Pure-Dart validator for the new-appointment / edit-appointment form.
/// Returns a `Map<fieldName, AppointmentFormError>` of errors. An empty
/// map means the form is valid.
class AppointmentFormValidator {
  const AppointmentFormValidator._();

  static Map<String, AppointmentFormError> validate(
    AppointmentFormInput input,
  ) {
    final errors = <String, AppointmentFormError>{};

    if (input.title.trim().isEmpty) {
      errors['title'] = AppointmentFormError.titleRequired;
    }
    if (input.date == null) {
      errors['date'] = AppointmentFormError.dateRequired;
    }
    if (input.startTime == null) {
      errors['startTime'] = AppointmentFormError.startTimeRequired;
    }

    if (input.endTime == null) {
      errors['endTime'] = AppointmentFormError.endTimeRequired;
    } else if (input.date != null && input.startTime != null) {
      // Use the same "smart end combine" the existing form does so overnight
      // appointments (start 11pm, end 1am) don't fail this check.
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

    if (input.client == null) {
      errors['client'] = AppointmentFormError.clientRequired;
    }
    if (input.selectedEmployees.isEmpty) {
      errors['employees'] = AppointmentFormError.employeesRequired;
    }

    return errors;
  }
}

/// Composes a calendar date and a wall-clock time into a single `DateTime`
/// on the same day.
DateTime combineDateAndTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);

/// Same as `combineDateAndTime`, but bumps the end into the next day when
/// the wall-clock end is at or before the start time. Lets the form
/// represent overnight appointments (e.g. start 11pm, end 1am) without
/// failing the "end must be after start" check.
DateTime combineEndDateAndTime(
  DateTime date,
  TimeOfDay endTime, [
  TimeOfDay? startTime,
]) {
  final end = combineDateAndTime(date, endTime);
  if (startTime == null) return end;
  final start = combineDateAndTime(date, startTime);
  return end.isAfter(start) ? end : end.add(const Duration(days: 1));
}
