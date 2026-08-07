import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/fade_in_item.dart';

/// The day's agenda rows as slivers — the skeleton, the empty state or the
/// card list. Sliver-shaped so the portrait calendar can scroll it in one
/// viewport with the month grid, which is what makes the grid collapse possible
/// at all. [AgendaHeader] is a separate widget because it is the calendar
/// tour's target and a showcase cannot wrap a sliver.
class AgendaSliverList extends StatelessWidget {
  const AgendaSliverList({
    required this.events,
    required this.nameMap,
    required this.colorMap,
    super.key,
    this.isAdmin = true,
    this.isLoading = false,
    this.onAppointmentTap,
    this.selectedAppointmentId,
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

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        if (isLoading)
          const SliverToBoxAdapter(child: _AgendaSkeleton())
        else if (events.isEmpty)
          SliverFillRemaining(
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
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp4),
            sliver: SliverList.builder(
              itemCount: events.length,
              itemBuilder: (context, index) {
                final slice = events[index];
                final e = slice.appointment;

                return FadeInItem(
                  key: ValueKey(e.id),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sp16,
                      vertical: AppSpacing.sp4,
                    ),
                    child: AppointmentCard(
                      appointment: e,
                      slice: slice,
                      crew: crewFor(e, colorMap: colorMap, nameMap: nameMap),
                      selected: selectedAppointmentId == e.id,
                      onTap: () {
                        if (onAppointmentTap != null) {
                          onAppointmentTap!(e);
                        } else {
                          showEventDetails(context, e, showActions: isAdmin);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The selected day's title and a mono job count.
class AgendaHeader extends StatelessWidget {
  const AgendaHeader({
    required this.dayTitle,
    required this.jobLabel,
    super.key,
  });

  final String dayTitle;
  final String jobLabel;

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
        ],
      ),
    );
  }
}

class _AgendaSkeleton extends StatelessWidget {
  const _AgendaSkeleton();

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
