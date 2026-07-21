import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/dashboard/domain/assignee_names.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Today's upcoming visits, rendered with the shared [AppointmentCard] so they
/// match the calendar list exactly.
class UpcomingTodaySection extends StatelessWidget {
  const UpcomingTodaySection({
    required this.ops,
    required this.colorMap,
    required this.nameMap,
    required this.isAdmin,
    super.key,
  });

  final TodayOps ops;
  final Map<String, Color> colorMap;
  final Map<String, String> nameMap;

  /// Gates the admin-only Edit/Cancel/Delete actions on the sheet a card opens.
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_upcomingToday),
        const SizedBox(height: AppSpacing.sp8),
        if (ops.upcoming.isEmpty)
          Text(
            l10n.dashboard_noVisitsToday,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (var i = 0; i < ops.upcoming.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sp8),
            AppointmentCard(
              appointment: ops.upcoming[i],
              employeeColor:
                  colorFromMap(ops.upcoming[i], colorMap) ?? scheme.outline,
              employeeName: resolveAssigneeNames(ops.upcoming[i], nameMap),
              onTap: () => showEventDetails(
                context,
                ops.upcoming[i],
                showActions: isAdmin,
              ),
            ),
          ],
      ],
    );
  }
}
