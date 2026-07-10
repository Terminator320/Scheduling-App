import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

Future<TimeOfDay?> showCupertinoTimePicker(
  BuildContext context, {
  TimeOfDay? initialTime,
}) {
  final now = DateTime.now();
  final init = initialTime ?? TimeOfDay.now();
  var tempPicked = DateTime(
    now.year,
    now.month,
    now.day,
    init.hour,
    init.minute,
  );

  return _showCupertinoWheelSheet<TimeOfDay>(
    context,
    onDone: () => TimeOfDay(hour: tempPicked.hour, minute: tempPicked.minute),
    wheelBuilder: (ctx) => CupertinoDatePicker(
      mode: CupertinoDatePickerMode.time,
      initialDateTime: tempPicked,
      use24hFormat: MediaQuery.alwaysUse24HourFormatOf(ctx),
      onDateTimeChanged: (dateTime) {
        tempPicked = dateTime;
      },
    ),
  );
}

/// Cupertino date wheel in the same bottom-sheet chrome as the time picker —
/// the iOS counterpart of Material's [showDatePicker].
Future<DateTime?> showCupertinoDatePickerSheet(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  var tempPicked = DateTime(
    initialDate.year,
    initialDate.month,
    initialDate.day,
  );
  if (tempPicked.isBefore(firstDate)) tempPicked = firstDate;
  if (tempPicked.isAfter(lastDate)) tempPicked = lastDate;
  final initial = tempPicked;

  return _showCupertinoWheelSheet<DateTime>(
    context,
    onDone: () => tempPicked,
    wheelBuilder: (ctx) => CupertinoDatePicker(
      mode: CupertinoDatePickerMode.date,
      initialDateTime: initial,
      minimumDate: firstDate,
      maximumDate: lastDate,
      onDateTimeChanged: (dateTime) {
        tempPicked = dateTime;
      },
    ),
  );
}

/// Shared bottom-sheet chrome for the Cupertino wheels: Cancel/Done header
/// above the wheel, sized past the bottom view padding so the wheel doesn't
/// sit under the home indicator.
Future<T?> _showCupertinoWheelSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) wheelBuilder,
  required T Function() onDone,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    sheetAnimationStyle: AppMotion.sheetStyle,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
    ),
    builder: (ctx) {
      return SizedBox(
        height: 300 + MediaQuery.viewPaddingOf(ctx).bottom,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Text(
                        ctx.l10n.common_cancel,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Text(
                        ctx.l10n.common_done,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, onDone()),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: wheelBuilder(ctx)),
            ],
          ),
        ),
      );
    },
  );
}
