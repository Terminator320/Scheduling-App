import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

class AppointmentTile extends StatelessWidget {
  const AppointmentTile({
    required this.appointment,
    required this.employeeColorMap,
    super.key,
    this.showActions = true,
    this.onOpen,
    this.alwaysShowChip = false,
    this.dimWhenCancelled = false,
  });
  final AppointmentRecord appointment;
  final bool showActions;
  final Map<String, Color> employeeColorMap;
  final Future<void> Function()? onOpen;

  /// Show the status chip even for confirmed appointments (the history list
  /// wants every row chipped; the calendar hides the chip when confirmed).
  final bool alwaysShowChip;

  /// Strike through the title and dim the card when the appointment is
  /// cancelled (history list treatment).
  final bool dimWhenCancelled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;
    final accent =
        colorFromMap(appointment, employeeColorMap) ?? scheme.primary;
    final status = AppointmentStatus.fromRaw(appointment.displayStatus);
    final showChip = alwaysShowChip || status != AppointmentStatus.confirmed;
    final isCancelled = dimWhenCancelled && status.isCancelled;

    final employeeName = appointment.employeeNames.isNotEmpty
        ? appointment.employeeNames.first
        : null;

    final timeLabel =
        '${DateUtilsHelper.formatTime(appointment.startTime)} - '
        '${DateUtilsHelper.formatTime(appointment.endTime)}'
        '${employeeName != null ? ' - $employeeName' : ''}';

    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (onOpen != null) {
            await onOpen!();
            return;
          }
          await showEventDetails(
            context,
            appointment,
            showActions: showActions,
          );
        },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sp12,
                    AppSpacing.sp8,
                    AppSpacing.sp8,
                    AppSpacing.sp8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              appointment.title,
                              maxLines: compact ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: isCancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isCancelled
                                    ? scheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ),
                          if (!compact && showChip) ...[
                            const SizedBox(width: AppSpacing.sp8),
                            StatusChip(status: status),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sp4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(top: AppSpacing.sp4),
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sp4),
                          Expanded(
                            child: Text(
                              timeLabel,
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (compact && showChip) ...[
                        const SizedBox(height: AppSpacing.sp8),
                        StatusChip(status: status),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  right: AppSpacing.sp8,
                  left: AppSpacing.sp4,
                ),
                child: Align(
                  alignment: compact ? Alignment.topCenter : Alignment.center,
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return isCancelled ? Opacity(opacity: 0.75, child: card) : card;
  }
}
