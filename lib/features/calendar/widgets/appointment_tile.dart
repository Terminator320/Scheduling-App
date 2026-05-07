import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

class AppointmentTile extends StatelessWidget {
  final AppointmentRecord appointment;
  final bool showActions;
  final Map<String, Color> employeeColorMap;
  final Future<void> Function()? onOpen;

  const AppointmentTile({
    super.key,
    required this.appointment,
    required this.employeeColorMap,
    this.showActions = true,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = colorFromMap(appointment, employeeColorMap) ?? AppColors.primary;
    final status = _mapStatus(appointment.status);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (onOpen != null) {
            await onOpen!();
            return;
          }
          await showEventDetails(context, appointment, showActions: showActions);
        },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        appointment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sp4),
                      Row(
                        children: [
                          Icon(Icons.access_time_outlined, size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${DateUtilsHelper.formatTime(appointment.startTime)} – ${DateUtilsHelper.formatTime(appointment.endTime)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp8),
                child: Center(child: StatusChip(status: status)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static AppointmentStatus _mapStatus(String status) =>
      switch (status.toLowerCase()) {
        'confirmed' => AppointmentStatus.confirmed,
        'done' || 'completed' => AppointmentStatus.done,
        'cancelled' => AppointmentStatus.cancelled,
        _ => AppointmentStatus.pending,
      };
}
