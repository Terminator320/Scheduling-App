import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_tile.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/clients/widgets/sections/history_filter_bar.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

class AppointmentHistoryView extends ConsumerStatefulWidget {
  const AppointmentHistoryView({required this.searchQuery, super.key});

  final String searchQuery;

  @override
  ConsumerState<AppointmentHistoryView> createState() =>
      _AppointmentHistoryViewState();
}

class _AppointmentHistoryViewState
    extends ConsumerState<AppointmentHistoryView> {
  int? _year;
  String? _employeeId;

  void _clearFilters() => setState(() {
    _year = null;
    _employeeId = null;
  });

  // Filter options are derived from the *full* history so a selection never
  // makes its own chip's other options disappear.
  List<int> _yearsOf(List<AppointmentRecord> appointments) {
    final years = <int>{for (final a in appointments) a.startTime.year};
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<HistoryEmployeeOption> _employeesOf(
    List<AppointmentRecord> appointments,
  ) {
    final names = <String, String>{};
    for (final a in appointments) {
      for (var i = 0; i < a.employeeIds.length; i++) {
        final id = a.employeeIds[i];
        if (id.isEmpty) continue;
        final name = i < a.employeeNames.length ? a.employeeNames[i] : '';
        final existing = names[id];
        if (existing == null || (existing.isEmpty && name.isNotEmpty)) {
          names[id] = name;
        }
      }
    }
    final options = [
      for (final e in names.entries)
        (id: e.key, name: e.value.isEmpty ? e.key : e.value),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return options;
  }

  List<AppointmentRecord> _applyFilters(List<AppointmentRecord> appointments) {
    final hasQuery = widget.searchQuery.trim().isNotEmpty;
    // Accent-folded text + digits-only phone matching — same rule as the
    // clients list, so a client's phone number finds their appointments.
    final qText = ClientSearchPolicy.normalize(widget.searchQuery);
    final qDigits = ClientSearchPolicy.digitsOnly(widget.searchQuery);
    return appointments.where((a) {
      if (_year != null && a.startTime.year != _year) return false;
      if (_employeeId != null && !a.employeeIds.contains(_employeeId)) {
        return false;
      }
      if (hasQuery) {
        if (qText.isEmpty && qDigits.isEmpty) return false;
        final matchesClient =
            qText.isNotEmpty &&
            ClientSearchPolicy.normalize(a.clientName).contains(qText);
        final matchesEmployee =
            qText.isNotEmpty &&
            a.employeeNames.any(
              (e) => ClientSearchPolicy.normalize(e).contains(qText),
            );
        final matchesPhone =
            qDigits.isNotEmpty &&
            ClientSearchPolicy.digitsOnly(a.clientPhone).contains(qDigits);
        if (!matchesClient && !matchesEmployee && !matchesPhone) return false;
      }
      return true;
    }).toList();
  }

  List<_HistoryRow> _buildRows(List<AppointmentRecord> filtered) {
    final locale = Intl.defaultLocale ?? 'en_CA';
    final dayFormat = DateFormat('EEEE, MMMM d', locale);
    final rows = <_HistoryRow>[];
    int? currentYear;
    DateTime? currentDay;
    for (final app in filtered) {
      final day = DateUtils.dateOnly(app.startTime);
      if (day.year != currentYear) {
        rows.add(_HistoryYearHeader(day.year));
        currentYear = day.year;
        currentDay = null;
      }
      if (day != currentDay) {
        rows.add(_HistoryDayHeader(dayFormat.format(day).toUpperCase()));
        currentDay = day;
      }
      rows.add(_HistoryCardRow(app));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colorMap = ref.watch(employeeColorMapProvider);
    final historyAsync = ref.watch(appointmentHistoryProvider);

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: historyAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.sp12),
          children: const [
            SkeletonListTile(),
            SizedBox(height: AppSpacing.sp8),
            SkeletonListTile(),
            SizedBox(height: AppSpacing.sp8),
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
          if (appointments.isEmpty) {
            return AppEmptyState(
              icon: Icons.history_outlined,
              title: context.l10n.common_noAppointmentsFound,
              body: context.l10n.common_tapToScheduleAnAppointment,
            );
          }

          final years = _yearsOf(appointments);
          final employees = _employeesOf(appointments);
          final filtered = _applyFilters(appointments);
          final showFilters = HistoryFilterBar.hasFilters(
            years: years,
            employees: employees,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showFilters)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sp8,
                    bottom: AppSpacing.sp4,
                  ),
                  child: HistoryFilterBar(
                    years: years,
                    selectedYear: _year,
                    onYearChanged: (v) => setState(() => _year = v),
                    employees: employees,
                    selectedEmployeeId: _employeeId,
                    onEmployeeChanged: (v) => setState(() => _employeeId = v),
                    allYearsLabel: context.l10n.clients_allYears,
                    allStaffLabel: context.l10n.clients_allStaff,
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(context)
                    : _buildList(filtered, colorMap),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    final query = widget.searchQuery.trim();
    final hasChipFilter = _year != null || _employeeId != null;

    if (query.isNotEmpty && !hasChipFilter) {
      return AppEmptyState(
        icon: Icons.search_off_outlined,
        title: '${l10n.clients_noAppointmentsMatch} "$query"',
        body: l10n.common_tryADifferentSearchTerm,
      );
    }
    return AppEmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: l10n.clients_noAppointmentsMatchFilters,
      body: l10n.common_tryADifferentSearchTerm,
      actionLabel: hasChipFilter ? l10n.clients_clearFilters : null,
      onAction: hasChipFilter ? _clearFilters : null,
    );
  }

  Widget _buildList(
    List<AppointmentRecord> filtered,
    Map<String, Color> colorMap,
  ) {
    final rows = _buildRows(filtered);
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sp12),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final nextRow = index + 1 < rows.length ? rows[index + 1] : null;
        return switch (row) {
          _HistoryYearHeader(:final year) => Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : AppSpacing.sp16,
              bottom: AppSpacing.sp8,
            ),
            child: _YearHeaderLabel(year),
          ),
          _HistoryDayHeader(:final label) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionLabel(label),
          ),
          _HistoryCardRow(:final appointment) => Padding(
            padding: EdgeInsets.only(
              bottom: nextRow is _HistoryCardRow ? 7 : AppSpacing.sp8,
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
  }
}

/// Bold year separator that opens each year's group in the list.
class _YearHeaderLabel extends StatelessWidget {
  const _YearHeaderLabel(this.year);

  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '$year',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: AppSpacing.sp12),
        Expanded(
          child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ),
      ],
    );
  }
}

sealed class _HistoryRow {
  const _HistoryRow();
}

class _HistoryYearHeader extends _HistoryRow {
  const _HistoryYearHeader(this.year);
  final int year;
}

class _HistoryDayHeader extends _HistoryRow {
  const _HistoryDayHeader(this.label);
  final String label;
}

class _HistoryCardRow extends _HistoryRow {
  const _HistoryCardRow(this.appointment);
  final AppointmentRecord appointment;
}
