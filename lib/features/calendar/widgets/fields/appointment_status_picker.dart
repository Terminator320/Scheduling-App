import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

class AppointmentStatusPicker extends StatelessWidget {
  const AppointmentStatusPicker({
    required this.currentStatus,
    required this.onChanged,
    super.key,
  });

  final String currentStatus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final selected = AppointmentStatus.fromRaw(currentStatus);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: AppointmentStatus.appointmentValues.map((s) {
        final isSelected = selected == s;
        return GestureDetector(
          onTap: () => onChanged(s.raw),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primaryContainer : Colors.transparent,
              border: Border.all(
                color: isSelected ? scheme.primary : scheme.outlineVariant,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(AppRadius.rFull),
            ),
            child: Text(
              statusLabel(l, s),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
