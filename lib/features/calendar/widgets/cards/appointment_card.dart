import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/tap_scale.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// The app's core component: one appointment, everywhere it appears — the
/// calendar agenda, the day route, client job history, the dashboard, and the
/// history list (which used to have its own `AppointmentTile`).
class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    required this.appointment,
    required this.crew,
    super.key,
    this.clientName,
    this.onTap,
    this.selected = false,
    this.footer,
    this.dimWhenCancelled = false,
    this.emphasizeToday = false,
  });

  final AppointmentRecord appointment;

  /// Assignees in order. Empty is legitimate — an unassigned job.
  final List<AppointmentCrew> crew;

  /// Overrides the record's denormalized client name (the client detail
  /// surfaces already know the live one).
  final String? clientName;

  final VoidCallback? onTap;
  final bool selected;

  /// Rendered below the meta rows — the day route's Navigate pill.
  final Widget? footer;

  /// Strikes the title through and drops the card to 0.6 opacity when the
  /// visit is cancelled. History and client job history want this; the day's
  /// agenda does not.
  final bool dimWhenCancelled;

  /// Today's cards use a 3px bar rather than 4px, per the design.
  final bool emphasizeToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;
    final status = AppointmentStatus.fromRaw(appointment.displayStatus);
    final isCancelled = dimWhenCancelled && status.isCancelled;

    final timeLabel =
        '${DateUtilsHelper.formatTime(appointment.startTime)} – '
        '${DateUtilsHelper.formatTime(appointment.endTime)}';

    // The bar follows the FIRST assignee: the crew line makes them the card's
    // identity, and the old per-appointment colour went grey for any job with
    // more than one person on it.
    final storedBar = crew.isEmpty ? null : crew.first.color;
    final barColor = storedBar == null
        ? theme.palette.textFaint
        : crewColorOf(theme, storedBar.toARGB32());

    final client = (clientName ?? appointment.clientName).trim();
    final crewLabel = _crewLabel(context);
    final metaLine = crewLabel == null
        ? client
        : client.isEmpty
        ? crewLabel
        : context.l10n.calendar_crewAndClient(crewLabel, client);

    final semanticsLabel = [
      appointment.title,
      statusLabel(context.l10n, status),
      timeLabel,
      for (final member in crew) member.name,
      if (client.isNotEmpty) client,
    ].join(', ');

    final card = TapScale(
      child: DecoratedBox(
        decoration: appCardDecoration(
          theme,
          radius: AppRadius.rCard,
          color: selected ? scheme.secondaryContainer : scheme.surface,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.rCard),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Semantics(
                label: semanticsLabel,
                excludeSemantics: true,
                // IntrinsicHeight stretches the crew bar to the card's full
                // height. Nothing inside this subtree may use LayoutBuilder,
                // AutoSizeText or FittedBox — they cannot report intrinsics.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: emphasizeToday ? 3 : 4, color: barColor),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: AppSpacing.cardPaddingY,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TitleRow(
                                title: appointment.title,
                                status: status,
                                compact: compact,
                                isCancelled: isCancelled,
                              ),
                              const SizedBox(height: 7),
                              Text(timeLabel, style: theme.monoType.data),
                              if (metaLine.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                _CrewRow(
                                  crew: crew,
                                  label: metaLine,
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
        ),
      ),
    );

    return isCancelled ? Opacity(opacity: 0.6, child: card) : card;
  }

  /// `Theo` for one assignee, `Theo +1` for more, null for none.
  String? _crewLabel(BuildContext context) {
    if (crew.isEmpty) return null;
    final first = _firstName(crew.first.name);
    if (crew.length == 1) return first;
    return context.l10n.calendar_crewPlusOthers(first, crew.length - 1);
  }

  static String _firstName(String name) {
    final trimmed = name.trim();
    final space = trimmed.indexOf(' ');
    return space == -1 ? trimmed : trimmed.substring(0, space);
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.status,
    required this.compact,
    required this.isCancelled,
  });

  final String title;
  final AppointmentStatus status;
  final bool compact;
  final bool isCancelled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A plain Text, never AutoSizeText — see the IntrinsicHeight note above.
    final titleText = Text(
      title,
      maxLines: compact ? 3 : 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        decoration: isCancelled ? TextDecoration.lineThrough : null,
        color: isCancelled ? theme.palette.textTertiary : null,
      ),
    );

    Widget titleContent = titleText;
    if (status == AppointmentStatus.overdue) {
      // The crew bar encodes identity, not status, so overdue needs its own
      // glyph.
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

    final chip = StatusChip(status: status);
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleContent),
        const SizedBox(width: AppSpacing.sp8),
        chip,
      ],
    );
  }
}

class _CrewRow extends StatelessWidget {
  const _CrewRow({
    required this.crew,
    required this.label,
    required this.compact,
  });

  final List<AppointmentCrew> crew;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (crew.isNotEmpty) ...[
          // AppAvatar resolves crewColorOf/avatarForegroundFor itself, so the
          // STORED colour goes straight through.
          AppAvatar(
            name: crew.first.name,
            color: crew.first.color,
            size: AvatarSize.xs,
          ),
          const SizedBox(width: AppSpacing.sp8),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.palette.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
