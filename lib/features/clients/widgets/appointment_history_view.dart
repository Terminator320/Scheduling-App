import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/app_empty_state.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

class AppointmentHistoryView extends ConsumerWidget {
  const AppointmentHistoryView({required this.searchQuery, super.key});

  final String searchQuery;

  static final _dateKeyFormat = DateFormat('yyyy-MM-dd');

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
        error: (err, st) {
          ref.read(loggerProvider).warn('history stream error', err, st);
          return Center(child: Text(context.l10n.error_somethingWentWrong));
        },
        data: (appointments) {
          final filtered = query.isEmpty
              ? appointments.toList()
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
                  ? context.l10n.common_noAppointmentsFound
                  : '${context.l10n.clients_noAppointmentsMatch} "$query"',
              body: query.isEmpty
                  ? context.l10n.common_tapToScheduleAnAppointment
                  : context.l10n.common_tryADifferentSearchTerm,
            );
          }

          filtered.sort((a, b) => b.startTime.compareTo(a.startTime));

          final locale = Intl.defaultLocale ?? 'en_CA';
          final dateHeaderFormat = DateFormat('EEEE, MMMM d', locale);

          final rows = <_HistoryRow>[];
          String? currentKey;
          for (final app in filtered) {
            final key = _dateKeyFormat.format(app.startTime);
            if (key != currentKey) {
              final label = dateHeaderFormat
                  .format(DateTime.parse(key))
                  .toUpperCase();
              rows.add(_HistoryHeader(label));
              currentKey = key;
            }
            rows.add(_HistoryCardRow(app));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final nextRow = index + 1 < rows.length ? rows[index + 1] : null;
              return switch (row) {
                _HistoryHeader(:final label) => Padding(
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
                _HistoryCardRow(:final appointment) => Padding(
                  padding: EdgeInsets.only(
                    bottom: nextRow is _HistoryCardRow ? 7 : 8,
                  ),
                  child: _HistoryCard(
                    appointment: appointment,
                    employeeColorMap: colorMap,
                  ),
                ),
              };
            },
          );
        },
      ),
    );
  }
}

sealed class _HistoryRow {
  const _HistoryRow();
}

class _HistoryHeader extends _HistoryRow {
  const _HistoryHeader(this.label);
  final String label;
}

class _HistoryCardRow extends _HistoryRow {
  const _HistoryCardRow(this.appointment);
  final AppointmentRecord appointment;
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
