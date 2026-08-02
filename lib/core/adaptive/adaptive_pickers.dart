import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/adaptive/cupertino_time_picker.dart';

/// Platform-adaptive date picker: Cupertino wheel on iOS/macOS, Material calendar elsewhere.
Future<DateTime?> showAdaptiveDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  if (context.isCupertino) {
    return showCupertinoDatePickerSheet(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  );
}

/// Platform-adaptive time picker: Cupertino wheel on iOS/macOS, Material picker elsewhere.
Future<TimeOfDay?> showAdaptiveTimePicker(
  BuildContext context, {
  TimeOfDay? initialTime,
}) {
  if (context.isCupertino) {
    return showCupertinoTimePicker(context, initialTime: initialTime);
  }
  return showTimePicker(
    context: context,
    initialTime: initialTime ?? TimeOfDay.now(),
  );
}
