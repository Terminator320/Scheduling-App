import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 280),
      reverseDuration: Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text(
                      ctx.l10n.cancel,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text(
                      ctx.l10n.done,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                    onPressed: () => Navigator.pop(
                      ctx,
                      TimeOfDay(
                        hour: tempPicked.hour,
                        minute: tempPicked.minute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: tempPicked,
                onDateTimeChanged: (dateTime) {
                  tempPicked = dateTime;
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
