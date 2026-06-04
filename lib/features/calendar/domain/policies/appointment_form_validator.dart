import 'package:flutter/material.dart' show TimeOfDay;

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
  });

  final String title;
  final DateTime? date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final ClientRecord? client;
  final List<EmployeeRecord> selectedEmployees;
}

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
  // Wall-clock next-day construction (not end.add(Duration(days: 1))) so an
  // overnight end landing on a DST transition day keeps its time-of-day.
  return end.isAfter(start)
      ? end
      : DateTime(
          date.year,
          date.month,
          date.day + 1,
          endTime.hour,
          endTime.minute,
        );
}

/// Returns [errors] without [key], or the same map untouched when absent —
/// used by the form controllers to clear a field's error as the user fixes it.
Map<String, AppointmentFormError> withoutKey(
  Map<String, AppointmentFormError> errors,
  String key,
) {
  if (!errors.containsKey(key)) return errors;
  return Map<String, AppointmentFormError>.from(errors)..remove(key);
}
