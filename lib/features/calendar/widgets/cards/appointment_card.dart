import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/tap_scale.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// How much of the crew the card shows — both the bands the colour bar splits
/// into and the avatars in the stack, deliberately the same number so the two
/// always agree. Past this a band is too thin to read and the stack outgrows
/// the meta line.
const int _kMaxCrewShown = 4;

/// The colour bar down the card's leading edge: a flat colour for one crew, a
/// hard-stopped gradient of everyone's colours for more. Deliberately NOT grey
/// for a multi-crew job — grey reads as "unassigned" and throws away the one
/// thing the bar is for (owner call, 2026-07-31).
BoxDecoration _crewBarDecoration(ThemeData theme, List<Color> colors) {
  if (colors.isEmpty) return BoxDecoration(color: theme.palette.textFaint);
  if (colors.length == 1) return BoxDecoration(color: colors.first);
  final step = 1 / colors.length;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      // Each colour twice against a shared stop, so the bands meet at a hard
      // edge instead of blending into mud.
      colors: [
        for (final color in colors) ...[color, color],
      ],
      stops: [
        for (var i = 0; i < colors.length; i++) ...[i * step, (i + 1) * step],
      ],
    ),
  );
}

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
    this.slice,
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

  /// This card's day within a multi-day run. Null for surfaces that show a job
  /// once (history, client job history) rather than per day.
  final AppointmentDaySlice? slice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;
    final status = AppointmentStatus.fromRaw(appointment.displayStatus);
    final isCancelled = dimWhenCancelled && status.isCancelled;

    final timeLabel = _timeLabel(context);

    // One band per crew member rather than the first assignee's colour alone:
    // a two-person job now reads as two-person at a glance, and nobody's colour
    // is thrown away. An assignee with no colour is skipped, not greyed.
    final barColors = [
      for (final member in crew.take(_kMaxCrewShown))
        if (member.color case final stored?)
          crewColorOf(theme, stored.toARGB32()),
    ];

    // A personal job has no client, so it names itself in that slot rather
    // than leaving the meta line as the crew alone.
    final client = appointment.isPersonal
        ? context.l10n.calendar_personal
        : (clientName ?? appointment.clientName).trim();
    // The crew is now the avatar stack, so the meta text is the client alone.
    // A job with no client to name (an unassigned legacy record) falls back to
    // the crew names rather than leaving the line blank.
    final metaLine = client.isNotEmpty ? client : (_crewLabel(context) ?? '');

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
                      Container(
                        width: emphasizeToday ? 3 : 4,
                        decoration: _crewBarDecoration(theme, barColors),
                      ),
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

  /// The card's mono time line, scoped to the day this card represents.
  ///
  /// The stored times are a DAILY window, so every day of a run reads the same
  /// clock — only the counter moves. "All day" is reserved for `isAllDay` and
  /// is never borrowed to describe a timed job's middle day.
  String _timeLabel(BuildContext context) {
    final l10n = context.l10n;
    final window = slice;
    final base = appointment.isAllDay
        ? l10n.calendar_allDay
        : '${DateUtilsHelper.formatTime(window?.windowStart ?? appointment.startTime)} – '
              '${DateUtilsHelper.formatTime(window?.windowEnd ?? appointment.endTime)}';
    if (window == null || !window.isMultiDay) return base;
    final counter = window.isOvernight
        ? l10n.calendar_nightOfCount(window.dayIndex, window.dayCount)
        : l10n.calendar_dayOfCount(window.dayIndex, window.dayCount);
    return '$base · $counter';
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

/// Every assignee's avatar, overlapped into a stack. Overlapping rather than
/// spacing them keeps a four-person job from eating the client's name; the
/// stack's width is computed rather than laid out, because the card's
/// `IntrinsicHeight` forbids a `LayoutBuilder` anywhere in this subtree.
class _CrewAvatars extends StatelessWidget {
  const _CrewAvatars({required this.crew});

  final List<AppointmentCrew> crew;

  /// How much of each avatar the next one covers. The diameter comes from
  /// [AvatarSize.xs] itself — the stack has to size itself by hand (no
  /// `LayoutBuilder` under `IntrinsicHeight`), so a local copy would silently
  /// drift if the avatar sizes ever changed.
  static const double _overlap = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = crew.take(_kMaxCrewShown).toList();
    final diameter = AvatarSize.xs.diameter;
    final step = diameter - _overlap;

    return SizedBox(
      width: diameter + (shown.length - 1) * step,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted right-to-left so each avatar overlaps the one after it,
          // which is what makes the stack read as a stack.
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: Container(
                // A hairline of the card's own colour keeps two adjacent crew
                // colours from bleeding into one shape.
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
                // AppAvatar resolves crewColorOf/avatarForegroundFor itself,
                // so the STORED colour goes straight through.
                child: AppAvatar(
                  name: shown[i].name,
                  color: shown[i].color,
                  size: AvatarSize.xs,
                ),
              ),
            ),
        ],
      ),
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
          _CrewAvatars(crew: crew),
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
