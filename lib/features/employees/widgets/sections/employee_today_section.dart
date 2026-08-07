import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// This person's stops today — a new `AppointmentCard` consumer.
///
/// Renders an explicit "No jobs today" rather than omitting itself: unlike the
/// info rows above it, an empty answer here is the answer.
class EmployeeTodaySection extends ConsumerWidget {
  const EmployeeTodaySection({
    required this.employeeId,
    required this.onJobTap,
    super.key,
  });

  final String employeeId;
  final void Function(String appointmentId) onJobTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final jobs = ref.watch(employeeTodayJobsProvider(employeeId));
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(context.l10n.employees_today),
        const SizedBox(height: AppSpacing.sp8),
        if (jobs.isEmpty)
          Text(
            context.l10n.employees_noJobsToday,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.palette.textTertiary,
            ),
          )
        else
          for (final job in jobs) ...[
            AppointmentCard(
              appointment: job,
              crew: crewFor(job, colorMap: colorMap, nameMap: nameMap),
              dimWhenCancelled: true,
              onTap: () => onJobTap(job.id ?? ''),
            ),
            const SizedBox(height: AppSpacing.sp8),
          ],
      ],
    );
  }
}
