import 'package:flutter/material.dart';

class AppointmentDraftDefaults {
  const AppointmentDraftDefaults._();

  /// Inclusive bounds for the appointment date picker, shared by the add and
  /// edit flows so the two pickers can't drift apart.
  static final DateTime datePickerFirstDate = DateTime(2020);
  static final DateTime datePickerLastDate = DateTime(2100);

  static TimeOfDay defaultEndTime(TimeOfDay startTime) {
    final minutes = startTime.hour * 60 + startTime.minute + 60;
    return TimeOfDay(
      hour: (minutes ~/ 60) % TimeOfDay.hoursPerDay,
      minute: minutes % TimeOfDay.minutesPerHour,
    );
  }
}
