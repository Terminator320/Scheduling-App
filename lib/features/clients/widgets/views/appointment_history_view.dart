import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_tile.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

class AppointmentHistoryView extends ConsumerWidget {
  const AppointmentHistoryView({required this.searchQuery, super.key});

  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = searchQuery.trim().toLowerCase();
    // Accent-folded matching — same rule as the server-side client search.
    final normalizedQuery = ClientSearchPolicy.normalize(searchQuery);
    final colorMap = ref.watch(employeeColorMapProvider);
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
          ref
              .read(loggerProvider)
              .warn('HIST-LOAD history stream error', err, st);
          return Center(
            child: Text(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introLoadHistory,
                tag: 'HIST-LOAD',
                error: err,
              ),
            ),
          );
        },
        data: (appointments) {
          // Already sorted newest-first by watchHistory.
          final filtered = query.isEmpty
              ? appointments
              : appointments.where((a) {
                  // A punctuation-only query normalizes to '' — contains('')
                  // matches everything, so treat it as matching nothing.
                  if (normalizedQuery.isEmpty) return false;
                  final matchesClient = ClientSearchPolicy.normalize(
                    a.clientName,
                  ).contains(normalizedQuery);
                  final matchesEmployee = a.employeeNames.any(
                    (e) => ClientSearchPolicy.normalize(
                      e,
                    ).contains(normalizedQuery),
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

          final locale = Intl.defaultLocale ?? 'en_CA';
          final dateHeaderFormat = DateFormat('EEEE, MMMM d', locale);

          final rows = <_HistoryRow>[];
          DateTime? currentDay;
          for (final app in filtered) {
            final day = DateUtils.dateOnly(app.startTime);
            if (day != currentDay) {
              rows.add(
                _HistoryHeader(dateHeaderFormat.format(day).toUpperCase()),
              );
              currentDay = day;
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
                  child: SectionLabel(label),
                ),
                _HistoryCardRow(:final appointment) => Padding(
                  padding: EdgeInsets.only(
                    bottom: nextRow is _HistoryCardRow ? 7 : 8,
                  ),
                  child: AppointmentTile(
                    appointment: appointment,
                    employeeColorMap: colorMap,
                    showActions: false,
                    alwaysShowChip: true,
                    dimWhenCancelled: true,
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
