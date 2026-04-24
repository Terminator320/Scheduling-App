import 'package:flutter/material.dart';
import '../../models/employee_record.dart';
import '../../services/appointment_service.dart';
import 'package:scheduling/models/appointment_record.dart';
import '../../utils/calendar_utils/appointment_colors.dart';
import '../../utils/date_utils_helper.dart';
import '../../utils/calendar_utils/sheet_helpers.dart';
import '../popup_widgets/details_edit_sheet.dart';

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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
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

  void _openEditSheet(BuildContext context, AppointmentRecord e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventDetailsSheet(
        appointment: e,
        showActions: isAdmin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ValueListenableBuilder<List<AppointmentRecord>>(
        valueListenable: events,
        builder: (context, value, _) {
          value.sort((a, b) => a.startTime.compareTo(b.startTime));

          if (value.isEmpty) {
            return const Center(child: Text("No events"));
          }

          return ListView.builder(
            itemCount: value.length,
            itemBuilder: (context, index) {
              final e = value[index];
              final empColor = colorForAppointment(e, employees);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                color: Theme.of(context).cardColor,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showEventDetails(context, e),
                  child: Row(
                    children: [
                      // Colored left bar
                      Container(
                        width: 5,
                        height: 70,
                        decoration: BoxDecoration(
                          color: empColor ?? Colors.grey.shade300,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            bottomLeft: Radius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Color dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: empColor ?? Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                "${DateUtilsHelper.formatTime(e.startTime)} - ${DateUtilsHelper.formatTime(e.endTime)}",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Boutons admin seulement
                      if (isAdmin) ...[
                        IconButton(
                          onPressed: () => _confirmDelete(context, e),
                          icon: const Icon(Icons.delete),
                          color: Colors.red,
                          tooltip: 'Delete',
                        ),
                        IconButton(
                          onPressed: () => _openEditSheet(context, e),
                          icon: const Icon(Icons.edit),
                          tooltip: 'Edit',
                        ),
                      ],
                    ],
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