
import 'package:flutter/material.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class TimeRangeRow extends StatelessWidget {

  const TimeRangeRow({
    required this.startController, required this.endController, required this.onTapStart, required this.onTapEnd, required this.selectedStart, required this.selectedEnd, super.key,
    this.startError,
    this.endError,
  });
  final TextEditingController startController;
  final TextEditingController endController;
  final VoidCallback onTapStart;
  final VoidCallback onTapEnd;
  final TimeOfDay? selectedStart;
  final TimeOfDay? selectedEnd;
  final String? startError;
  final String? endError;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: startController,
            readOnly: true,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: formInputDecoration(context, context.l10n.start)
                .copyWith(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: formInputDecoration(context, context.l10n.end).copyWith(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              errorText: endError,
            ),
            onTap: onTapEnd,
          ),
        ),
      ],
    );
  }
}
