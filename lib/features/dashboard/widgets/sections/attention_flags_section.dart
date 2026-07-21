import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/dashboard/domain/assignee_names.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Pending-soon and never-closed visits, rendered with the shared
/// [AppointmentCard] so they match the calendar list and the rest of the
/// dashboard exactly; the group header carries the severity, not the card.
class AttentionFlagsSection extends StatelessWidget {
  const AttentionFlagsSection({
    required this.flags,
    required this.colorMap,
    required this.nameMap,
    required this.isAdmin,
    super.key,
  });

  final AttentionFlags flags;
  final Map<String, Color> colorMap;
  final Map<String, String> nameMap;

  /// Gates the admin-only Edit/Cancel/Delete actions on the sheet a card opens.
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.statusColors;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_attentionFlags),
        const SizedBox(height: AppSpacing.sp8),
        if (flags.isAllClear)
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: statusColors.success,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  l10n.dashboard_allClear,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          )
        else ...[
          if (flags.pendingSoon.isNotEmpty)
            _FlagGroup(
              title: l10n.dashboard_pendingSoonHeader(flags.pendingSoon.length),
              appointments: flags.pendingSoon,
              colorMap: colorMap,
              nameMap: nameMap,
              isAdmin: isAdmin,
            ),
          if (flags.pendingSoon.isNotEmpty && flags.overdueOpen.isNotEmpty)
            const SizedBox(height: AppSpacing.sp16),
          if (flags.overdueOpen.isNotEmpty)
            _FlagGroup(
              title: l10n.dashboard_overdueOpenHeader(flags.overdueOpen.length),
              appointments: flags.overdueOpen,
              colorMap: colorMap,
              nameMap: nameMap,
              isAdmin: isAdmin,
            ),
        ],
      ],
    );
  }
}

class _FlagGroup extends StatelessWidget {
  const _FlagGroup({
    required this.title,
    required this.appointments,
    required this.colorMap,
    required this.nameMap,
    required this.isAdmin,
  });

  final String title;
  final List<AppointmentRecord> appointments;
  final Map<String, Color> colorMap;
  final Map<String, String> nameMap;

  /// Gates the admin-only actions on the sheet a card opens.
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sp8),
        for (var i = 0; i < appointments.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sp8),
          AppointmentCard(
            appointment: appointments[i],
            employeeColor:
                colorFromMap(appointments[i], colorMap) ?? scheme.outline,
            employeeName: resolveAssigneeNames(appointments[i], nameMap),
            onTap: () => showEventDetails(
              context,
              appointments[i],
              showActions: isAdmin,
            ),
          ),
        ],
      ],
    );
  }
}
