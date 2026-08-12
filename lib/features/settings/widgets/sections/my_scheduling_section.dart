import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';

/// The daily cap options: no cap, then 1–12, which covers any real crew day.
/// Mirrors the admin edit sheet's list — the same field, offered the same way.
const _kMaxJobsOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/// Scheduling limits on My details — **admin-only**.
///
/// `maxJobsPerDay` is NOT on the self-service rules allowlist, so this writes
/// through the ADMIN branch of `allow update`. That is also why a technician
/// gets nothing rather than a disabled control: there is no path here that
/// could ever succeed for them, and an inert row would advertise a dead end.
///
/// Deliberately scoped to this one field. Role, job title and crew colour stay
/// on the admin Team sheet — an admin editing their own role from a
/// self-service screen is a privilege-escalation shape with no product reason
/// to exist.
class MySchedulingSection extends StatelessWidget {
  const MySchedulingSection({
    required this.isAdmin,
    required this.maxJobsPerDay,
    required this.onChanged,
    super.key,
  });

  final bool isAdmin;
  final int maxJobsPerDay;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) return const SizedBox.shrink();
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonoSectionLabel(l10n.settings_myScheduling),
        const SizedBox(height: AppSpacing.sp16),
        SheetPanel(
          children: [
            SheetFieldRow(
              key: const Key('myMaxJobsPerDay'),
              label: l10n.employees_maxJobsPerDay,
              value: maxJobsPerDay == 0
                  ? l10n.employees_noCap
                  : '$maxJobsPerDay',
              useMonoValue: true,
              onTap: () => _pick(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final l10n = context.l10n;
    final picked = await showAdaptiveActionSheet<int>(
      context,
      title: l10n.employees_maxJobsPerDay,
      actions: [
        for (final option in _kMaxJobsOptions)
          AdaptiveSheetAction(
            label: option == 0 ? l10n.employees_noCap : '$option',
            value: option,
          ),
      ],
    );
    // The host is stateful and its callback reads `context.l10n` and calls
    // `setState`, so a screen popped while the sheet is open must not reach it.
    if (picked == null || !context.mounted) return;
    onChanged(picked);
  }
}
