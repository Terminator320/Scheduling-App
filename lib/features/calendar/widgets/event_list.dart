import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/details_edit_sheet.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/shared/widgets/app_empty_state.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';

class EventList extends StatelessWidget {
  final ValueNotifier<List<AppointmentRecord>> events;
  final List<EmployeeRecord> employees;
  final bool isAdmin;
  final bool isLoading;

  const EventList({
    super.key,
    required this.events,
    required this.employees,
    this.isAdmin = true,
    this.isLoading = false,
  });

  Future<void> _confirmDelete(BuildContext context, AppointmentRecord e) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteJob),
        content: Text(ctx.l10n.areYouSureYouWantToDeleteThisJob),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (e.id == null) return;
    await AppointmentService.deleteAppointment(e.id!);
  }

  Future<void> _openEditSheet(BuildContext context, AppointmentRecord e) async {
    final updated = await showModalBottomSheet<AppointmentRecord>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EventDetailsSheet(
          appointment: e,
          showActions: isAdmin,
          initialEditing: true,
        ),
    );

    if (updated != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.appointmentUpdated)),
        );
      }
    }
  }

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
    final colorMap = buildEmployeeColorMap(employees);

    return Expanded(
      child: isLoading
          ? _buildSkeleton()
          : ValueListenableBuilder<List<AppointmentRecord>>(
        valueListenable: events,
        builder: (context, value, _) {
          if (value.isEmpty) {
            return AppEmptyState(
              icon: Icons.event_outlined,
              title: context.l10n.noAppointmentsFound,
              body: context.l10n.tapToScheduleAnAppointment,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp4),
            itemCount: value.length,
            itemBuilder: (context, index) {
              final e = value[index];
              final accent = colorFromMap(e, colorMap) ?? scheme.outline;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sp16,
                  vertical: AppSpacing.sp4,
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => showEventDetails(context, e),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(width: 5, color: accent),
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
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    e.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: AppSpacing.sp4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.access_time_outlined,
                                        size: 13,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: AppSpacing.sp4),
                                      Expanded(
                                        child: Text(
                                        "${DateUtilsHelper.formatTime(e.startTime)} – ${DateUtilsHelper.formatTime(e.endTime)}",
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isAdmin) ...[
                            IconButton(
                              onPressed: () => _openEditSheet(context, e),
                              icon: const Icon(Icons.edit_outlined),
                              color: scheme.onSurfaceVariant,
                              tooltip: context.l10n.edit,
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              onPressed: () => _confirmDelete(context, e),
                              icon: const Icon(Icons.delete_outline),
                              color: scheme.error,
                              tooltip: context.l10n.delete,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: AppSpacing.sp4),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Center(
                                child: Icon(
                                  Icons.chevron_right,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
