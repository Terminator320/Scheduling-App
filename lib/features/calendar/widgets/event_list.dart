import 'package:flutter/material.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/details_edit_sheet.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';

class EventList extends StatelessWidget {
  final ValueNotifier<List<AppointmentRecord>> events;
  final List<EmployeeRecord> employees;
  final bool isAdmin;

  const EventList({
    super.key,
    required this.events,
    required this.employees,
    this.isAdmin = true,
  });

  Future<void> _confirmDelete(BuildContext context, AppointmentRecord e) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job'),
        content: const Text('Are you sure you want to delete this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (e.id == null) return;
    await AppointmentService.deleteAppointment(e.id!);
  }

  void _openEditSheet(BuildContext context, AppointmentRecord e) async {
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
          const SnackBar(content: Text('Appointment updated')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colorMap = buildEmployeeColorMap(employees);

    return Expanded(
      child: ValueListenableBuilder<List<AppointmentRecord>>(
        valueListenable: events,
        builder: (context, value, _) {
          if (value.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 40,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "No events",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: value.length,
            itemBuilder: (context, index) {
              final e = value[index];
              final accent = colorFromMap(e, colorMap) ?? scheme.outline;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
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
                                14,
                                12,
                                8,
                                12,
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
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.access_time_outlined,
                                        size: 13,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
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
                              tooltip: 'Edit',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              onPressed: () => _confirmDelete(context, e),
                              icon: const Icon(Icons.delete_outline),
                              color: scheme.error,
                              tooltip: 'Delete',
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
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
