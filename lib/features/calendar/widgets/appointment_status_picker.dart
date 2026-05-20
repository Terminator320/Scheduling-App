import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

class AppointmentStatusPicker extends StatelessWidget {
  const AppointmentStatusPicker({
    required this.currentStatus,
    required this.onChanged,
    super.key,
  });

  final String currentStatus;
  final ValueChanged<String> onChanged;

  static const _statuses = <String>[
    'confirmed',
    'in_progress',
    'pending',
    'done',
    'cancelled',
  ];

  String _labelFor(AppLocalizations l, String s) => switch (s) {
    'confirmed' => l.status_confirmed,
    'in_progress' => l.status_inProgress,
    'pending' => l.status_pending,
    'done' => l.status_done,
    'cancelled' => l.status_cancelled,
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final selected = currentStatus.toLowerCase();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _statuses.map((s) {
        final isSelected = selected == s;
        return GestureDetector(
          onTap: () => onChanged(s),
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
              _labelFor(l, s),
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
