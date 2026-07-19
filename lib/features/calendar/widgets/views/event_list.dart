import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/fade_in_item.dart';

class EventList extends StatelessWidget {
  const EventList({
    required this.events,
    required this.nameMap,
    required this.colorMap,
    super.key,
    this.isAdmin = true,
    this.isLoading = false,
    this.onAppointmentTap,
    this.onSchedule,
    this.selectedAppointmentId,
  });
  final ValueNotifier<List<AppointmentRecord>> events;
  final Map<String, String> nameMap;
  final Map<String, Color> colorMap;
  final bool isAdmin;
  final bool isLoading;
  final void Function(AppointmentRecord appointment)? onAppointmentTap;

  /// Admin-only "schedule for the selected day" action wired into the empty
  /// state so the most common landing (an empty day) has a one-tap booking
  /// affordance instead of making the admin hunt for the FAB.
  final VoidCallback? onSchedule;
  final String? selectedAppointmentId;

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp8,
      ),
      children: const [
        SkeletonAppointmentRow(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonAppointmentRow(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonAppointmentRow(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Expanded(
      child: isLoading
          ? _buildSkeleton()
          : ValueListenableBuilder<List<AppointmentRecord>>(
              valueListenable: events,
              builder: (context, value, _) {
                if (value.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.event_outlined,
                    title: context.l10n.common_noAppointmentsFound,
                    // Only admins have the "+" FAB, so don't tell employees
                    // to tap a button that isn't there.
                    body: isAdmin
                        ? context.l10n.common_tapToScheduleAnAppointment
                        : context.l10n.calendar_noAppointmentsForDay,
                    actionLabel: isAdmin && onSchedule != null
                        ? context.l10n.calendar_newAppointment
                        : null,
                    onAction: isAdmin ? onSchedule : null,
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp4),
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final e = value[index];
                    final accent = colorFromMap(e, colorMap) ?? scheme.outline;
                    // Show every assigned employee, not just the first —
                    // dropping any id the name map can't resolve and any blank
                    // name (so no stray ", " separators).
                    final joinedNames = e.employeeIds
                        .map((id) => nameMap[id])
                        .whereType<String>()
                        .where((name) => name.isNotEmpty)
                        .join(', ');
                    final employeeName = joinedNames.isEmpty
                        ? null
                        : joinedNames;

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
                          employeeColor: accent,
                          employeeName: employeeName,
                          selected: selectedAppointmentId == e.id,
                          onTap: () {
                            if (onAppointmentTap != null) {
                              onAppointmentTap!(e);
                            } else {
                              showEventDetails(
                                context,
                                e,
                                showActions: isAdmin,
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
