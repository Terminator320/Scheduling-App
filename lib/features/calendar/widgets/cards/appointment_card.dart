import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/tap_scale.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    required this.appointment,
    required this.employeeColor,
    super.key,
    this.employeeName,
    this.onTap,
    this.selected = false,
    this.footer,
  });

  final AppointmentRecord appointment;
  final Color employeeColor;
  final String? employeeName;
  final VoidCallback? onTap;
  final bool selected;

  /// Optional widget rendered inside the padded column below the meta rows
  /// (e.g. the day-route navigate pill). Existing call sites pass nothing.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = context.isCompact;
    final status = AppointmentStatus.fromRaw(appointment.displayStatus);
    final timeLabel =
        '${DateUtilsHelper.formatTime(appointment.startTime)} - '
        '${DateUtilsHelper.formatTime(appointment.endTime)}';
    final name = employeeName;

    // One coherent screen-reader read for the whole card instead of the title,
    // status, time, and name surfacing as disjoint fragments inside the button.
    final semanticsLabel = [
      appointment.title,
      statusLabel(context.l10n, status),
      timeLabel,
      ?name,
    ].join(', ');

    return TapScale(
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: selected ? scheme.secondaryContainer : null,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            label: semanticsLabel,
            excludeSemantics: true,
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
                          _TitleHeader(
                            title: appointment.title,
                            status: status,
                            compact: compact,
                          ),
                          const SizedBox(height: AppSpacing.sp4),
                          _TimeRow(timeLabel: timeLabel, compact: compact),
                          if (name != null) ...[
                            const SizedBox(height: AppSpacing.sp4),
                            _EmployeeRow(
                              name: name,
                              color: employeeColor,
                              compact: compact,
                            ),
                          ],
                          if (footer != null) ...[
                            const SizedBox(height: AppSpacing.sp8),
                            footer!,
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
      ),
    );
  }
}

class _TitleHeader extends StatelessWidget {
  const _TitleHeader({
    required this.title,
    required this.status,
    required this.compact,
  });

  final String title;
  final AppointmentStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Plain Text (not AutoSizeText): this card lives under IntrinsicHeight,
    // which can't measure an AutoSizeText's internal LayoutBuilder.
    final titleText = Text(
      title,
      maxLines: compact ? 3 : 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium,
    );
    final chip = StatusChip(status: status);

    // Overdue jobs get a leading warning glyph so they pop when scanning a busy
    // multi-plumber day list — the employee-color bar is identity, not status
    // (the StatusChip still carries the textual "Overdue" state).
    Widget titleContent = titleText;
    if (status == AppointmentStatus.overdue) {
      titleContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: AppSpacing.sp4),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: theme.statusColors.warning,
            ),
          ),
          Expanded(child: titleText),
        ],
      );
    }

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleContent,
          const SizedBox(height: AppSpacing.sp8),
          chip,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: titleContent),
        const SizedBox(width: AppSpacing.sp8),
        chip,
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.timeLabel, required this.compact});

  final String timeLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(
          Icons.access_time_outlined,
          size: 13,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sp4),
        Expanded(
          child: Text(
            timeLabel,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.name,
    required this.color,
    required this.compact,
  });

  final String name;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sp4),
        Expanded(
          child: Text(
            name,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
