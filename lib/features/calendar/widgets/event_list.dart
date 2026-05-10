import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/appointment_card.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
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
    final nameMap = {for (final emp in employees) emp.id: emp.name};

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
              final employeeName = e.employeeIds.isNotEmpty
                  ? nameMap[e.employeeIds.first]
                  : null;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sp16,
                  vertical: AppSpacing.sp4,
                ),
                child: AppointmentCard(
                  appointment: e,
                  employeeColor: accent,
                  employeeName: employeeName,
                  onTap: () => showEventDetails(context, e),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
