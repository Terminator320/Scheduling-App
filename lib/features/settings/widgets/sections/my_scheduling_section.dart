import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';

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
    final picked = await showMaxJobsPicker(context);
    // The host is stateful and its callback reads `context.l10n` and calls
    // `setState`, so a screen popped while the sheet is open must not reach it.
    if (picked == null || !context.mounted) return;
    onChanged(picked);
  }
}
