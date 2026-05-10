import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/app_empty_state.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

/// Body of the appointment-history mode (route: `/clients` with mode = history).
class AppointmentHistoryView extends ConsumerWidget {
  const AppointmentHistoryView({required this.searchQuery, super.key});

  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = searchQuery.trim().toLowerCase();
    final employees =
        ref.watch(allUsersStreamProvider).asData?.value ??
        const <EmployeeRecord>[];
    final colorMap = buildEmployeeColorMap(employees);
    final historyAsync = ref.watch(appointmentHistoryProvider);

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: historyAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(12),
          children: const [
            SkeletonListTile(),
            SizedBox(height: 8),
            SkeletonListTile(),
            SizedBox(height: 8),
            SkeletonListTile(),
          ],
        ),
        error: (_, _) => Center(child: Text(context.l10n.somethingWentWrong)),
        data: (appointments) {
          final filtered = query.isEmpty
              ? appointments
              : appointments.where((a) {
                  final matchesClient = a.clientName.toLowerCase().contains(
                    query,
                  );
                  final matchesEmployee = a.employeeNames.any(
                    (e) => e.toLowerCase().contains(query),
                  );
                  return matchesClient || matchesEmployee;
                }).toList();

          if (filtered.isEmpty) {
            return AppEmptyState(
              icon: query.isEmpty
                  ? Icons.history_outlined
                  : Icons.search_off_outlined,
              title: query.isEmpty
                  ? context.l10n.noAppointmentsFound
                  : '${context.l10n.noAppointmentsMatch} "$query"',
              body: query.isEmpty
                  ? context.l10n.tapToScheduleAnAppointment
                  : context.l10n.tryADifferentSearchTerm,
            );
          }

          filtered.sort((a, b) => b.startTime.compareTo(a.startTime));

          final locale = Intl.defaultLocale ?? 'en_CA';
          final dateKeyFormat = DateFormat('yyyy-MM-dd');
          final dateHeaderFormat = DateFormat('EEEE, MMMM d', locale);

          final grouped = <String, List<AppointmentRecord>>{};
          for (final app in filtered) {
            final key = dateKeyFormat.format(app.startTime);
            grouped.putIfAbsent(key, () => []).add(app);
          }

          final sortedKeys = grouped.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          final items = <Widget>[];
          for (final key in sortedKeys) {
            final group = grouped[key]!;
            final date = DateTime.parse(key);
            final label = dateHeaderFormat.format(date).toUpperCase();

            items.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            );

            for (var i = 0; i < group.length; i++) {
              items.add(
                _HistoryCard(
                  appointment: group[i],
                  employeeColorMap: colorMap,
                ),
              );
              if (i < group.length - 1) {
                items.add(const SizedBox(height: 7));
              }
            }
            items.add(const SizedBox(height: 8));
          }

          return ListView(padding: const EdgeInsets.all(12), children: items);
        },
      ),
    );
  }
}

AppointmentStatus _mapHistoryStatus(String status) =>
    switch (status.toLowerCase()) {
      'confirmed' => AppointmentStatus.confirmed,
      'done' || 'completed' => AppointmentStatus.done,
      'cancelled' => AppointmentStatus.cancelled,
      'in_progress' || 'inprogress' => AppointmentStatus.inProgress,
      _ => AppointmentStatus.pending,
    };

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.appointment,
    required this.employeeColorMap,
  });

  final AppointmentRecord appointment;
  final Map<String, Color> employeeColorMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCancelled = appointment.status.toLowerCase() == 'cancelled';
    final accent =
        colorFromMap(appointment, employeeColorMap) ?? scheme.primary;
    final status = _mapHistoryStatus(appointment.displayStatus);

    final employeeName = appointment.employeeNames.isNotEmpty
        ? appointment.employeeNames.first
        : null;

    final timeLabel =
        '${DateUtilsHelper.formatTime(appointment.startTime)} – ${DateUtilsHelper.formatTime(appointment.endTime)}'
        '${employeeName != null ? ' · $employeeName' : ''}';

    Widget card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showEventDetails(context, appointment, showActions: false),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        appointment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          decoration: isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                          color: isCancelled ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              timeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
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
              Padding(
                padding: const EdgeInsets.only(right: 10, left: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(status: status),
                    const SizedBox(width: 7),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isCancelled) {
      card = Opacity(opacity: 0.75, child: card);
    }

    return card;
  }
}
