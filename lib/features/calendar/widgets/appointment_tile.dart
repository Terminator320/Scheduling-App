import 'package:flutter/material.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';

class AppointmentTile extends StatelessWidget {
  final AppointmentRecord appointment;

  const AppointmentTile({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        onTap: () => showEventDetails(context, appointment),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateUtilsHelper.formatPrettyDate(appointment.startTime),
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
        title: Text(
          appointment.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, size: 13),
                const SizedBox(width: 4),
                Text(appointment.clientName),
              ],
            ),
            if (appointment.employeeNames.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.group, size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      appointment.employeeNames.join(', '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
        isThreeLine: appointment.employeeNames.isNotEmpty,
      ),
    );
  }
}
