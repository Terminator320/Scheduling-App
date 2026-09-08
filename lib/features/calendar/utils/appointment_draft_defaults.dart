import 'package:flutter/material.dart';

class AppointmentDraftDefaults {
  const AppointmentDraftDefaults._();

  /// Inclusive bounds for the appointment date picker (shared to keep add and edit flows in sync).
  static final DateTime datePickerFirstDate = DateTime(2020);
  static final DateTime datePickerLastDate = DateTime(2100);

  /// The plain one-hour default, which WRAPS past midnight (23:30 -> 00:30);
  /// [endTimeFor] clamps instead, and that is the only difference between them.
  static TimeOfDay defaultEndTime(TimeOfDay startTime) {
    final minutes =
        startTime.hour * TimeOfDay.minutesPerHour +
        startTime.minute +
        TimeOfDay.minutesPerHour;
    return TimeOfDay(
      hour: (minutes ~/ TimeOfDay.minutesPerHour) % TimeOfDay.hoursPerDay,
      minute: minutes % TimeOfDay.minutesPerHour,
    );
  }

  /// End time [durationMinutes] after [startTime], clamped inside the day.
  static TimeOfDay endTimeFor(TimeOfDay startTime, int durationMinutes) {
    final minutes =
        (startTime.hour * TimeOfDay.minutesPerHour +
                startTime.minute +
                durationMinutes)
            .clamp(0, Duration.minutesPerDay - 1);
    return TimeOfDay(
      hour: minutes ~/ TimeOfDay.minutesPerHour,
      minute: minutes % TimeOfDay.minutesPerHour,
    );
  }
}
