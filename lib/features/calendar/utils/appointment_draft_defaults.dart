import 'package:flutter/material.dart';

class AppointmentDraftDefaults {
  const AppointmentDraftDefaults._();

  static TimeOfDay defaultEndTime(TimeOfDay startTime) {
    final minutes = startTime.hour * 60 + startTime.minute + 60;
    return TimeOfDay(
      hour: (minutes ~/ 60) % TimeOfDay.hoursPerDay,
      minute: minutes % TimeOfDay.minutesPerHour,
    );
  }
}
