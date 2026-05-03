import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/tap_scale.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    required this.appointment,
    required this.employeeColor,
    super.key,
    this.employeeName,
    this.onTap,
    this.selected = false,
  });

  final AppointmentRecord appointment;
  final Color employeeColor;
  final String? employeeName;
  final VoidCallback? onTap;
  final bool selected;

  AppointmentStatus _statusFromString(String status) =>
      switch (status.toLowerCase()) {
        'done' || 'completed' => AppointmentStatus.done,
        'cancelled' => AppointmentStatus.cancelled,
        'pending' => AppointmentStatus.pending,
        'in_progress' || 'inprogress' => AppointmentStatus.inProgress,
        _ => AppointmentStatus.confirmed,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TapScale(
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: selected ? scheme.secondaryContainer : null,
        child: InkWell(
          onTap: onTap,
          // InkWell already exposes button semantics and reads the visible
          // title, status, and time; no explicit Semantics label needed.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: employeeColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sp12,
                      AppSpacing.sp12,
                      AppSpacing.sp8,
                      AppSpacing.sp12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                appointment.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sp8),
                            StatusChip(
                              status: _statusFromString(
                                appointment.displayStatus,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sp4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_outlined,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.sp4),
                            Text(
                              '${DateUtilsHelper.formatTime(appointment.startTime)} – ${DateUtilsHelper.formatTime(appointment.endTime)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (employeeName != null) ...[
                          const SizedBox(height: AppSpacing.sp4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: employeeColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sp4),
                              Text(
                                employeeName!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
