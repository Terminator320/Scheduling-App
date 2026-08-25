import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/tap_scale.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/day_off_reason.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// How much of the crew the card shows — both the bands the colour bar splits
/// into and the avatars in the stack, deliberately the same number so the two
/// always agree. Past this a band is too thin to read and the stack outgrows
/// the meta line.
const int _kMaxCrewShown = 4;

/// The day-off strip's dashed rail geometry: inset from the leading edge,
/// stroke width, and the gap between it and the avatar. Named because the
/// rail is POSITIONED (from [_kRailInset], [_kRailWidth]) while the content is
/// PADDED past it by all three — the two spellings have to agree, or the rail
/// paints under the avatar.
const double _kRailInset = 9;
const double _kRailWidth = 3;
const double _kRailGap = 10;

/// Vertical padding inside the day-off strip. Its 44px floor still wins for a
/// single-line (untitled) block.
const double _kStripPaddingY = 9;

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
    this.collapseWhenClosed = false,
    this.slice,
  });

  /// Minimum height of a collapsed row's body.
  ///
  /// The collapsed padding + title + meta line lands near 56px, which already
  /// clears Material's 48px minimum — but not by enough to leave to chance at
  /// the OS's smallest text scale. Pinning it makes the tap target structural
  /// rather than incidental. Growing the other way needs nothing: the body is a
  /// Column, so large text simply makes the row taller.
  static const double _kClosedMinHeight = 48;

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
  /// visit is cancelled. History, client job history and — since closed jobs
  /// sank into their own block — the day's agenda all want this.
  final bool dimWhenCancelled;

  /// Today's cards use a 3px bar rather than 4px, per the design.
  final bool emphasizeToday;

  /// The calendar agenda's sunk-block treatment for a closed job: the green
  /// success tint for `done`, and a collapsed body that puts the time beside
  /// the client and drops the crew avatars.
  ///
  /// Opt-in because the agenda is the only surface that SORTS closed work to
  /// the bottom — everywhere else a finished job still sits in context, where
  /// shrinking it would just hide information.
  final bool collapseWhenClosed;

  /// This card's day within a multi-day run. Null for surfaces that show a job
  /// once (history, client job history) rather than per day.
  final AppointmentDaySlice? slice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // TIME OFF is not a job, so it is not a card: no crew colour bar, no fill,
    // no shadow — a low strip that reads as a fact about the day rather than
    // an item in the list. It lives HERE rather than at the call sites because
    // `AppointmentCard` is the one appointment card, so every surface that
    // renders appointments gets the same treatment for free.
    if (appointment.isTimeOff) {
      return _DayOffStrip(
        appointment: appointment,
        crew: crew,
        onTap: onTap,
      );
    }

    final model = _CardModel.from(context, this);

    final card = TapScale(
      child: DecoratedBox(
        decoration: appCardDecoration(
          theme,
          radius: AppRadius.rCard,
          color: _cardColor(theme, model),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.rCard),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Semantics(
                label: model.semanticsLabel,
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
                        decoration: _crewBarDecoration(
                          theme,
                          _barColors(theme),
                        ),
                      ),
                      Expanded(child: _body(theme, model)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return model.isCancelled ? Opacity(opacity: 0.6, child: card) : card;
  }

  /// One band per crew member rather than the first assignee's colour alone: a
  /// two-person job reads as two-person at a glance, and nobody's colour is
  /// thrown away. An assignee with no colour is skipped, not greyed.
  ///
  /// Capped at [_kMaxCrewShown] — the SAME cap the avatar stack uses, so the
  /// bands and the faces can never disagree about how much of the crew the
  /// card is showing.
  List<Color> _barColors(ThemeData theme) => [
    for (final member in crew.take(_kMaxCrewShown))
      if (member.color case final stored?)
        crewColorOf(theme, stored.toARGB32()),
  ];

  /// The card's fill.
  ///
  /// Selection wins outright; a collapsed *done* job otherwise takes the same
  /// success token the "Complete" chip fills with, so the card and its own
  /// chip can't disagree. (In light the two are the same green anyway.)
  Color _cardColor(ThemeData theme, _CardModel model) {
    if (selected) return theme.colorScheme.secondaryContainer;
    if (model.collapsed && model.status.isDone) {
      return theme.statusColors.successContainer;
    }
    return theme.colorScheme.surface;
  }

  /// The card's text column — full height, or the agenda's collapsed row for a
  /// closed job.
  ///
  /// Collapsed drops the crew avatars and puts the time beside the client on
  /// one line. The colour bar still carries the crew, so *who* survives the
  /// collapse; only the faces go.
  Widget _body(ThemeData theme, _CardModel model) {
    final titleRow = _TitleRow(
      title: appointment.title,
      status: model.status,
      isTimeOff: model.isTimeOff,
      compact: model.compact,
      isCancelled: model.isCancelled,
      hasPhotos: model.hasPhotos,
    );

    if (model.collapsed) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kClosedMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              const SizedBox(height: 5),
              _ClosedMetaRow(time: model.timeLabel, label: model.metaLine),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: AppSpacing.cardPaddingY,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow,
          const SizedBox(height: 7),
          Text(model.timeLabel, style: theme.monoType.data),
          if (model.metaLine.isNotEmpty) ...[
            const SizedBox(height: 7),
            _CrewRow(crew: crew, label: model.metaLine, compact: model.compact),
          ],
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.sp8),
            footer!,
          ],
        ],
      ),
    );
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

/// A day off, in place of the card.
///
/// Reads the typed reason as the headline with `<name> is off` beneath it, and
/// once the last day has passed `<name> was off` with the Complete chip a
/// finished job wears — see [AppointmentRecord.displayStatusAt], which derives
/// that from the clock rather than from any write.
///
/// ONE layout serves both cases (owner call, 2026-08-25): the headline slot is
/// ALWAYS filled — the reason when there is one, the sentence when there isn't
/// — and only the caption below it is conditional. An untitled block therefore
/// renders its sentence a little heavier than it used to (`titleSmall` rather
/// than `bodyMedium`); that is the accepted price of one row shape instead of
/// two that drift apart. Never render both slots from the same string.
///
/// The crew colour comes back as a DASHED rail, reversing what this comment
/// said until 2026-08-25 — that the colour survived only as the avatar, since
/// "the BAR is what says a crew is on this job, and a day off has no job to be
/// on". The dashes are the reason it can: they read as the negative of the
/// card's solid bar rather than a quieter version of it, and they are what
/// lets two stacked absences be told apart before any text is read. What still
/// keeps this from reading as a card holds unchanged — no card fill, no
/// shadow, and a headline one size below the card's title.
class _DayOffStrip extends StatelessWidget {
  const _DayOffStrip({
    required this.appointment,
    required this.crew,
    required this.onTap,
  });

  final AppointmentRecord appointment;
  final List<AppointmentCrew> crew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final displayStatus = AppointmentStatus.fromRaw(appointment.displayStatus);
    final isOver = displayStatus.isTerminal;
    // The crew is who the block is FOR, so the sentence names them rather than
    // the title — a day off usually has none typed, and an untitled one would
    // otherwise read "Personal".
    final crewLabel = _crewLabel(context);
    final name = crewLabel ?? appointment.title.trim();
    final sentence = isOver
        ? l10n.calendar_dayOffWasOff(name)
        : l10n.calendar_dayOffIsOff(name);
    final reason = dayOffReason(
      title: appointment.title,
      hasSubject: crewLabel != null,
      placeholders: personalTitlePlaceholders,
    );
    final lead = crew.isEmpty ? null : crew.first;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Semantics(
          label: [?reason, sentence, l10n.calendar_dayOff].join(', '),
          excludeSemantics: true,
          // The rail is positioned rather than laid out in the Row so the
          // strip keeps sizing to its text — a stretched Row child would need
          // an IntrinsicHeight to resolve its own height first.
          child: Stack(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: EdgeInsets.only(
                  left: lead == null
                      ? AppSpacing.sp12
                      : _kRailInset + _kRailWidth + _kRailGap,
                  right: AppSpacing.sp12,
                  top: _kStripPaddingY,
                  bottom: _kStripPaddingY,
                ),
                decoration: BoxDecoration(
                  color: theme.statusColors.neutralContainer,
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                  // Load-bearing: that fill resolves to `AppColors.paper`,
                  // which is also `scaffoldBackgroundColor`, so in the light
                  // theme the strip has no container at all without an edge —
                  // two stacked days off run together.
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Row(
                  children: [
                    if (lead != null) ...[
                      Opacity(
                        opacity: isOver ? 0.55 : 1,
                        child: AppAvatar(
                          name: lead.name,
                          color: lead.color,
                          size: AvatarSize.xs,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sp8),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reason ?? sentence,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: isOver
                                  ? theme.palette.textTertiary
                                  : theme.palette.textBody,
                            ),
                          ),
                          if (reason != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              sentence,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.palette.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sp8),
                    // The finished state borrows the job chip so "done" looks
                    // the same everywhere; the open state is a caption, not a
                    // status.
                    if (isOver)
                      StatusChip(status: displayStatus)
                    else
                      Text(
                        l10n.calendar_dayOff.toUpperCase(),
                        style: theme.monoType.groupLabel,
                      ),
                  ],
                ),
              ),
              if (lead != null)
                Positioned(
                  left: _kRailInset,
                  top: AppSpacing.sp8,
                  bottom: AppSpacing.sp8,
                  width: _kRailWidth,
                  child: Opacity(
                    opacity: isOver ? 0.5 : 1,
                    child: CustomPaint(
                      // A null stored colour means the assignee no longer
                      // resolves to an employee — `AppointmentCrew` has the
                      // call site substitute a neutral, and the card's crew
                      // bar uses this same one. Never `colorScheme.primary`:
                      // `crewColorOf` keys on STORED light-theme hues, so the
                      // dark primary misses the override map and takes the
                      // generic lift on top of an already-lifted colour.
                      painter: _DashedRailPainter(
                        lead.color == null
                            ? theme.palette.textFaint
                            : crewColorOf(theme, lead.color!.toARGB32()),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// `Marc Tremblay` for one assignee, `Marc Tremblay +1` for more.
  String? _crewLabel(BuildContext context) {
    if (crew.isEmpty) return null;
    final first = crew.first.name.trim();
    if (crew.length == 1) return first;
    return context.l10n.calendar_crewPlusOthers(first, crew.length - 1);
  }
}

/// The day-off strip's leading rail: 4 on, 4 off, down the full inner height.
/// See [_DayOffStrip] for why a day off gets dashes where a job gets a bar.
class _DashedRailPainter extends CustomPainter {
  const _DashedRailPainter(this.color);

  final Color color;

  static const double _dash = 4;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final radius = Radius.circular(size.width / 2);
    for (var top = 0.0; top < size.height; top += _dash + _gap) {
      final bottom = (top + _dash).clamp(0.0, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top, size.width, bottom),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRailPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Everything `build` derives before it builds anything: the three variant
/// flags (compact / collapsed / cancelled), the two composed strings and the
/// spoken label.
///
/// Pulled out because `_body` needed most of them and was taking them one
/// named parameter at a time — eight of them, which is what made the three
/// variants hard to read side by side.
class _CardModel {
  const _CardModel({
    required this.status,
    required this.isTimeOff,
    required this.compact,
    required this.collapsed,
    required this.isCancelled,
    required this.hasPhotos,
    required this.timeLabel,
    required this.metaLine,
    required this.semanticsLabel,
  });

  factory _CardModel.from(BuildContext context, AppointmentCard card) {
    final appointment = card.appointment;
    final status = AppointmentStatus.fromRaw(appointment.displayStatus);
    final timeLabel = card._timeLabel(context);
    // The denormalized count, which trails a fresh upload by the recount
    // debounce. Fine for an indicator; see AppointmentRecord.hasPictures for
    // why it must not gate a read.
    final hasPhotos = appointment.hasPictures;

    // A personal job has no client, so it names itself in that slot rather
    // than leaving the meta line as the crew alone.
    final client = appointment.isPersonal
        ? context.l10n.calendar_personal
        : (card.clientName ?? appointment.clientName).trim();

    return _CardModel(
      status: status,
      isTimeOff: appointment.isTimeOff,
      compact: context.isCompact,
      collapsed: card.collapseWhenClosed && appointment.isClosed,
      isCancelled: card.dimWhenCancelled && status.isCancelled,
      hasPhotos: hasPhotos,
      timeLabel: timeLabel,
      // The crew is now the avatar stack, so the meta text is the client
      // alone. A job with no client to name (an unassigned legacy record)
      // falls back to the crew names rather than leaving the line blank.
      metaLine: client.isNotEmpty ? client : (card._crewLabel(context) ?? ''),
      semanticsLabel: [
        appointment.title,
        statusLabel(context.l10n, status),
        timeLabel,
        for (final member in card.crew) member.name,
        if (client.isNotEmpty) client,
        // The glyph is the only cue that a job carries photos, so it has to be
        // spoken — the card excludes its subtree's own semantics.
        if (hasPhotos) context.l10n.calendar_hasPhotos,
      ].join(', '),
    );
  }

  final AppointmentStatus status;

  /// Time off wears a "Day off" chip where the status normally sits — the card
  /// still renders in full, it just isn't work. See
  /// [AppointmentRecord.isTimeOff].
  final bool isTimeOff;
  final bool compact;
  final bool collapsed;
  final bool isCancelled;
  final bool hasPhotos;
  final String timeLabel;
  final String metaLine;
  final String semanticsLabel;
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.status,
    required this.isTimeOff,
    required this.compact,
    required this.isCancelled,
    required this.hasPhotos,
  });

  final String title;
  final AppointmentStatus status;
  final bool isTimeOff;
  final bool compact;
  final bool isCancelled;
  final bool hasPhotos;

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

    // The crew bar encodes identity, not status, so overdue needs its own glyph.
    final warning = status == AppointmentStatus.overdue
        ? Padding(
            padding: const EdgeInsets.only(top: 2, right: AppSpacing.sp4),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: theme.statusColors.warning,
            ),
          )
        : null;

    // The photo cue rides the title rather than the time line, so it reaches
    // the eye first and — because this row is shared — survives the agenda's
    // collapsed treatment, where the meta line loses the crew avatars.
    final photos = hasPhotos
        ? const Padding(
            padding: EdgeInsets.only(top: 2, left: AppSpacing.sp8),
            child: _PhotoGlyph(),
          )
        : null;

    Widget titleContent = titleText;
    if (warning != null || photos != null) {
      titleContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?warning,
          Expanded(child: titleText),
          ?photos,
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

/// A closed job's single meta line: the mono time, then the client.
///
/// The time keeps its multi-day counter — a 5-day run marked done still shows
/// on every one of its days, and without "Day 2 of 5" those rows are
/// indistinguishable from each other.
class _ClosedMetaRow extends StatelessWidget {
  const _ClosedMetaRow({required this.time, required this.label});

  final String time;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.monoType.data.copyWith(
              color: theme.palette.textTertiary,
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sp8 + 2),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.palette.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The card's "this job has photos" cue, at the end of the title line and just
/// before the status chip. Presence only — the count lives in the detail sheet,
/// and the card is answering "is there anything to look at here", not "how
/// much".
///
/// Semantics are excluded because the card composes one label for the whole
/// subtree; [AppointmentCard] adds the spoken form there.
class _PhotoGlyph extends StatelessWidget {
  const _PhotoGlyph();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.photo_outlined,
    size: 15,
    color: Theme.of(context).palette.textTertiary,
  );
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
