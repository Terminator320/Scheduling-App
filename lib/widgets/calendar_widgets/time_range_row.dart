
import 'package:flutter/material.dart';
import '../../utils/calendar_utils/form_widgets.dart';

class TimeRangeRow extends StatelessWidget {
  final TextEditingController startController;
  final TextEditingController endController;
  final VoidCallback onTapStart;
  final VoidCallback onTapEnd;
  final TimeOfDay? selectedStart;
  final TimeOfDay? selectedEnd;
  final String? startError;
  final String? endError;

  const TimeRangeRow({
    super.key,
    required this.startController,
    required this.endController,
    required this.onTapStart,
    required this.onTapEnd,
    required this.selectedStart,
    required this.selectedEnd,
    this.startError,
    this.endError,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: startController,
            readOnly: true,
            decoration: formInputDecoration(context, "Start time").copyWith(
              suffixIcon: const Icon(Icons.access_time_outlined, size: 18),
              errorText: startError,
            ),
            onTap: onTapStart,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: endController,
            readOnly: true,
            decoration: formInputDecoration(context, "End time").copyWith(
              suffixIcon: const Icon(Icons.access_time_outlined, size: 18),
              errorText: endError,
            ),
            onTap: onTapEnd,
          ),
        ),
      ],
    );
  }
}