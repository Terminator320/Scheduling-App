import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget formLabel(BuildContext context, String text, {bool optional = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.labelMedium),
        if (optional)
          Text(
            " (optional)",
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

Widget formSectionLabel(BuildContext context, String text) {
  return Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

InputDecoration formInputDecoration(BuildContext context, String hint) {
  final scheme = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hint,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.error, width: 1.5),
    ),
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

Future<TimeOfDay?> showCupertinoTimePicker(
  BuildContext context, {
  TimeOfDay? initialTime,
}) {
  final now = DateTime.now();
  final init = initialTime ?? TimeOfDay.now();
  DateTime tempPicked = DateTime(
    now.year,
    now.month,
    now.day,
    init.hour,
    init.minute,
  );

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
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
                      'Cancel',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text(
                      'Done',
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
                use24hFormat: false,
                minuteInterval: 1,
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

Widget formRemoveButton(BuildContext context) {
  return Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.scrim.withOpacity(0.54),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.close, size: 14, color: Colors.white),
  );
}
