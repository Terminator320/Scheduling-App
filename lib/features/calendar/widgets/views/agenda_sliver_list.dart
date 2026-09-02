import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/holidays.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/calendar/widgets/views/holiday_agenda_row.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/fade_in_item.dart';

/// Bottom gap a host must leave when it floats controls over this list: the
/// calendar's 58px FAB and its "Today" pill both sit 16px above the bottom of
/// the body, so without it the LAST card of the day scrolls to a rest position
/// underneath them and can neither be read nor tapped.
const double kAgendaFloatingControlsClearance = 90;

/// The day's agenda rows as slivers — the skeleton, the empty state or the
/// card list. Sliver-shaped so the portrait calendar can scroll it in one
/// viewport with the month grid, which is what makes the grid collapse possible
/// at all. [AgendaHeader] is a separate widget because it is the calendar
/// tour's target and a showcase cannot wrap a sliver.
class AgendaSliverList extends StatelessWidget {
  const AgendaSliverList({
    required this.events,
    required this.day,
    required this.nameMap,
    required this.colorMap,
    super.key,
    this.isAdmin = true,
    this.isLoading = false,
    this.onAppointmentTap,
    this.selectedAppointmentId,
    this.bottomClearance = 0,
    this.inWeek = false,
  });

  /// One entry per day the job runs — a multi-day job appears in the agenda of
  /// every day it spans, each slice carrying that day's window and counter.
  final List<AppointmentDaySlice> events;
  final Map<String, String> nameMap;
  final Map<String, Color> colorMap;
  final bool isAdmin;
  final bool isLoading;
  final void Function(AppointmentRecord appointment)? onAppointmentTap;
  final String? selectedAppointmentId;

  /// Extra scrollable extent below the last card, so a host that floats
  /// controls over the list can scroll the last job clear of them — pass
  /// [kAgendaFloatingControlsClearance]. Default 0: a pane with nothing
  /// floating over it must not grow dead space at the bottom.
  final double bottomClearance;

  /// One day of the week agenda rather than the whole agenda. The host draws
  /// ONE skeleton for the week and its own holiday rows, so this renders
  /// neither; an empty day is a quiet one-line row rather than a
  /// `SliverFillRemaining`, which would claim the rest of the viewport for
  /// each of seven days. It also returns a SINGLE sliver, never a group: the
  /// host puts it under a pinned day bar inside a `SliverMainAxisGroup`, and
  /// a group nested there lays the bar out with a clipped paint extent.
  final bool inWeek;

  /// The day this agenda describes, used only to look up its holidays.
  ///
  /// Owned here rather than at the two call sites (the portrait calendar and
  /// the split-layout `EventList`) so the row can never appear on one and not
  /// the other. It must be the SAME day [events] were resolved for.
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    // Computed, so it costs no read and does not wait on the jobs query — which
    // is why it renders above the skeleton and the empty state too. A holiday
    // with nothing booked is exactly the day this row has most to say about.
    // A LIST because the two Easters coincide roughly one year in three, and
    // the grid can only paint one hue on a shared day.
    final holidays = holidaysOn(day);
    if (inWeek) return events.isEmpty ? _emptyState(context) : _jobList();

    return SliverMainAxisGroup(
      slivers: [
        if (holidays.isNotEmpty) holidayRows(holidays),
        if (isLoading)
          const SliverToBoxAdapter(child: AgendaSkeleton())
        else if (events.isEmpty)
          _emptyState(context)
        else
          _jobList(),
      ],
    );
  }

  /// The day's holiday rows, above its jobs. Public so the week agenda draws
  /// the same rows beside its day bars.
  static Widget holidayRows(List<Holiday> holidays) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.sp16,
      AppSpacing.sp8,
      AppSpacing.sp16,
      0,
    ),
    sliver: SliverList.list(
      children: [
        for (final holiday in holidays) HolidayAgendaRow(holiday: holiday),
      ],
    ),
  );

  Widget _emptyState(BuildContext context) {
    if (inWeek) {
      final theme = Theme.of(context);
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sp16 + 2,
            AppSpacing.sp8,
            AppSpacing.sp16,
            AppSpacing.sp12,
          ),
          child: Text(
            context.l10n.calendar_noJobsThisDay,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.palette.textTertiary,
            ),
          ),
        ),
      );
    }
    return SliverFillRemaining(
      hasScrollBody: false,
      child: AppEmptyState(
        icon: Icons.event_outlined,
        title: context.l10n.common_noAppointmentsFound,
        // Only admins have the '+' FAB, so don't tell employees to tap a
        // button that isn't there.
        body: isAdmin
            ? context.l10n.common_tapToScheduleAnAppointment
            : context.l10n.calendar_noAppointmentsForDay,
      ),
    );
  }

  Widget _jobList() {
    // Where the day's remaining work ends, or -1 when nothing is closed.
    // `expandToDays` already sorts open before closed, so the closed jobs are
    // one contiguous run at the tail — which is what lets the rule be a single
    // marker at this index and its count a plain `length - index`. Resolved
    // once here, never inside the item builder, which runs per row per rebuild.
    final firstClosedIndex = events.indexWhere(
      (slice) => slice.appointment.isClosed,
    );
    // The rule's count must answer the header's question, or the two disagree
    // on the same block, so it filters through the same `countsAsWork`:
    // a completed DAY OFF and a CANCELLED visit both sink into the closed tail
    // and are rendered there, but neither is a job the day's work included, so
    // `_jobLabel` counts neither. Counted here rather than taken from
    // `length - index` for that reason — the cards below the rule and the
    // number on it are deliberately allowed to differ by exactly those.
    final closedJobCount = events
        .skip(firstClosedIndex < 0 ? events.length : firstClosedIndex)
        .where((slice) => countsAsWork(slice.appointment))
        .length;
    // With nothing FINISHED to announce the rule is suppressed entirely rather
    // than drawn reading "Done · 0" — which is what a day holding only
    // cancellations would otherwise get, since those still sink to the tail.
    final showClosedRule = firstClosedIndex >= 0 && closedJobCount > 0;

    return SliverPadding(
      // The clearance rides on the LIST branch only: the empty state is
      // a `SliverFillRemaining` that deliberately doesn't scroll, and
      // padding it would give it scrollable extent it has no content for.
      padding: EdgeInsets.only(
        top: AppSpacing.sp4,
        bottom: AppSpacing.sp4 + bottomClearance,
      ),
      sliver: SliverList.builder(
        itemCount: events.length,
        itemBuilder: (context, index) {
          final card = _card(context, events[index]);
          return FadeInItem(
            key: ValueKey(events[index].appointment.id),
            index: index,
            child: showClosedRule && index == firstClosedIndex
                ? Column(
                    children: [
                      _ClosedRule(count: closedJobCount),
                      card,
                    ],
                  )
                : card,
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, AppointmentDaySlice slice) {
    final e = slice.appointment;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp4,
      ),
      child: AppointmentCard(
        appointment: e,
        slice: slice,
        crew: crewFor(e, colorMap: colorMap, nameMap: nameMap),
        selected: selectedAppointmentId == e.id,
        collapseWhenClosed: true,
        dimWhenCancelled: true,
        onTap: () {
          if (onAppointmentTap != null) {
            onAppointmentTap!(e);
          } else {
            showEventDetails(context, e, showActions: isAdmin);
          }
        },
      ),
    );
  }
}

/// The rule between the day's remaining work and the jobs that are finished or
/// cancelled. It reads "Done" (owner call) even though cancelled visits sink
/// into the same block — the count covers both.
class _ClosedRule extends StatelessWidget {
  const _ClosedRule({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16 + 2,
        AppSpacing.sp12,
        AppSpacing.sp16 + 2,
        AppSpacing.sp4,
      ),
      child: Row(
        children: [
          Text(
            context.l10n.calendar_closedCount(count).toUpperCase(),
            style: theme.monoType.label.copyWith(
              color: theme.palette.textTertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.sp8 + 2),
          const Expanded(child: Divider(height: 1, thickness: 1)),
        ],
      ),
    );
  }
}

/// The selected day's title and a mono job count.
class AgendaHeader extends StatelessWidget {
  const AgendaHeader({
    required this.dayTitle,
    required this.jobLabel,
    super.key,
    this.trailing,
  });

  final String dayTitle;
  final String jobLabel;

  /// A control after the count — the day/week toggle. Must not grow the row:
  /// the calendar's overflow margin is pinned against this header's height.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: AppSpacing.sp8),
          Text(jobLabel, style: theme.monoType.data),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sp8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Three placeholder rows while the day's (or the week's) jobs load.
class AgendaSkeleton extends StatelessWidget {
  const AgendaSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppSpacing.sp16,
      vertical: AppSpacing.sp8,
    ),
    child: Column(
      children: [
        SkeletonAppointmentRow(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonAppointmentRow(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonAppointmentRow(),
      ],
    ),
  );
}
