import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/launchers/route_map_launcher.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/route_url_builder.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// A job is still "to drive to" (numbered on the timeline and included in the
/// launched multi-stop route) while its status is non-terminal.
bool _isOpen(String status) => !AppointmentStatus.fromRaw(status).isTerminal;

/// A day's jobs as a numbered route timeline, with per-stop navigation and a
/// pinned multi-stop Google Maps hand-off. Admins pick which employee to view.
class DayRouteScreen extends ConsumerStatefulWidget {
  const DayRouteScreen({
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final bool isAdmin;
  final String employeeId;

  @override
  ConsumerState<DayRouteScreen> createState() => _DayRouteScreenState();
}

class _DayRouteScreenState extends ConsumerState<DayRouteScreen> {
  late DateTime _day;
  late String _selectedEmployeeId;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now().dateOnly;
    _selectedEmployeeId = widget.employeeId;
  }

  AppointmentDateRange _dayRange(DateTime day) {
    final start = day.dateOnly;
    return AppointmentDateRange(
      start: start,
      end: start.add(const Duration(days: 1)),
    );
  }

  // The admin picker lists only employees with a job on the viewed day, so the
  // selection can point at someone who has nothing on the newly-picked day;
  // fall back to the first assignee. Non-admins always view their own jobs.
  String _resolveEmployeeId(List<String> assigneeIds) {
    if (!widget.isAdmin) return widget.employeeId;
    if (assigneeIds.isEmpty) return _selectedEmployeeId;
    return assigneeIds.contains(_selectedEmployeeId)
        ? _selectedEmployeeId
        : assigneeIds.first;
  }

  // Fires only on the data→error transition, mirroring the main calendar; a
  // `.when` error branch would re-log/notify on every rebuild.
  void _onAppointmentsAsyncChange(
    AsyncValue<List<AppointmentRecord>>? previous,
    AsyncValue<List<AppointmentRecord>> next,
  ) {
    if (next is! AsyncError || previous is AsyncError) return;
    ref
        .read(loggerProvider)
        .warn('APPT-LOAD day route stream error', next.error, next.stackTrace);
    if (!mounted) return;
    ref
        .read(noticeServiceProvider)
        .error(
          composeErrorNotice(
            context,
            intro: context.l10n.error_introLoadAppointments,
            tag: 'APPT-LOAD',
            error: next.error ?? Exception('unknown'),
          ),
        );
  }

  void _launchRoute(List<String> stops) {
    if (stops.length > maxRouteStops) {
      ref
          .read(noticeServiceProvider)
          .info(context.l10n.calendar_dayRouteTruncated);
    }
    final uri = buildGoogleMapsRouteUrl(stops);
    if (uri != null) launchGoogleMapsRoute(context, ref, uri);
  }

  @override
  Widget build(BuildContext context) {
    final range = _dayRange(_day);

    // Admins read the whole day (admin rule) so the picker can list only the
    // employees who actually have a job that day, and so switching assignees
    // needs no second query. Employees read just their own visible jobs.
    final provider = widget.isAdmin
        ? appointmentsInRangeProvider(range)
        : myAppointmentsProvider((employeeId: widget.employeeId, range: range));
    final async = ref.watch(provider);
    ref.listen(provider, _onAppointmentsAsyncChange);

    final dayAppointments =
        (async.value ?? const <AppointmentRecord>[])
            .where((a) => !AppointmentStatus.fromRaw(a.status).isCancelled)
            .toList()
          // The range query already returns startTime order; sort defensively so
          // numbering and the launched route stay in driving order regardless.
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Admin picker options: distinct employees assigned to a job that day,
    // ordered by name. Names come from the users map, falling back to the
    // appointment's denormalized names so a since-removed assignee still reads.
    final assigneeEntries = widget.isAdmin
        ? _assigneesWithJobs(dayAppointments)
        : const <MapEntry<String, String>>[];
    final employeeId = _resolveEmployeeId([
      for (final e in assigneeEntries) e.key,
    ]);

    // The selected employee's jobs. For an employee the query already scoped
    // it; for an admin, filter the whole-day list down to the picked assignee.
    final jobs = widget.isAdmin
        ? dayAppointments
              .where((a) => a.employeeIds.contains(employeeId))
              .toList()
        : dayAppointments;
    final stops = jobs
        .where(
          (a) => _isOpen(a.status) && a.address.trim().isNotEmpty,
        )
        .map((a) => a.address)
        .toList();

    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.calendar_dayRouteTitle,
        onBack: () => Navigator.pop(context),
        compact: context.isLandscape,
      ),
      bottomNavigationBar: _routeButton(stops),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _daySwitcher(),
            if (widget.isAdmin && assigneeEntries.isNotEmpty)
              _employeePicker(assigneeEntries, employeeId),
            Expanded(child: _timeline(async, jobs, employeeId)),
          ],
        ),
      ),
    );
  }

  // Distinct `id -> display name` for every employee assigned to a job in
  // [dayAppointments], ordered by name for a stable picker.
  List<MapEntry<String, String>> _assigneesWithJobs(
    List<AppointmentRecord> dayAppointments,
  ) {
    final nameMap = ref.watch(employeeNameMapProvider);
    final byId = <String, String>{};
    for (final a in dayAppointments) {
      for (var i = 0; i < a.employeeIds.length; i++) {
        final id = a.employeeIds[i];
        if (id.isEmpty) continue;
        byId.putIfAbsent(
          id,
          () =>
              nameMap[id] ??
              (i < a.employeeNames.length ? a.employeeNames[i] : id),
        );
      }
    }
    return byId.entries.toList()..sort(
      (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
    );
  }

  Widget _daySwitcher() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final label = DateFormat.MMMMEEEEd(
      Localizations.localeOf(context).toString(),
    ).format(_day);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: AppSpacing.sp8,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: l10n.calendar_dayRoutePreviousDay,
            onPressed: () =>
                setState(() => _day = _day.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.calendar_dayRouteNextDay,
            onPressed: () =>
                setState(() => _day = _day.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }

  Widget _employeePicker(
    List<MapEntry<String, String>> assignees,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        0,
        AppSpacing.sp16,
        AppSpacing.sp8,
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: context.l10n.calendar_dayRouteEmployeeLabel,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sp16,
            vertical: AppSpacing.sp12,
          ),
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        items: [
          for (final e in assignees)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) {
          if (id != null) setState(() => _selectedEmployeeId = id);
        },
      ),
    );
  }

  Widget _routeButton(List<String> stops) {
    final launchCount = stops.length > maxRouteStops
        ? maxRouteStops
        : stops.length;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        0,
        AppSpacing.sp16,
        AppSpacing.sp16,
      ),
      child: FilledButton.icon(
        icon: const Icon(Icons.alt_route_rounded),
        label: Text(context.l10n.calendar_dayRouteOpenInMaps(launchCount)),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r16),
          ),
        ),
        onPressed: stops.isEmpty ? null : () => _launchRoute(stops),
      ),
    );
  }

  Widget _timeline(
    AsyncValue<List<AppointmentRecord>> async,
    List<AppointmentRecord> jobs,
    String employeeId,
  ) {
    final l10n = context.l10n;
    if (async.isLoading && !async.hasValue) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: const [
          SkeletonAppointmentRow(),
          SizedBox(height: AppSpacing.sp8),
          SkeletonAppointmentRow(),
          SizedBox(height: AppSpacing.sp8),
          SkeletonAppointmentRow(),
        ],
      );
    }
    if (jobs.isEmpty) {
      return AppEmptyState(
        icon: Icons.alt_route_rounded,
        title: l10n.calendar_dayRouteEmptyTitle,
        body: l10n.calendar_dayRouteEmptyBody,
      );
    }

    // Number only open stops, in time (list) order; done stops get a ✓ badge.
    final numbers = <int?>[];
    var open = 0;
    for (final j in jobs) {
      numbers.add(_isOpen(j.status) ? ++open : null);
    }
    final empColor =
        ref.watch(employeeColorMapProvider)[employeeId] ??
        Theme.of(context).colorScheme.primary;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        AppSpacing.sp8,
        AppSpacing.sp16,
        AppSpacing.sp16,
      ),
      itemCount: jobs.length,
      itemBuilder: (context, i) => _StopTile(
        job: jobs[i],
        number: numbers[i],
        employeeColor: empColor,
        showConnector: i < jobs.length - 1,
        navigateLabel: l10n.calendar_dayRouteNavigate,
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.job,
    required this.number,
    required this.employeeColor,
    required this.showConnector,
    required this.navigateLabel,
  });

  final AppointmentRecord job;
  final int? number;
  final Color employeeColor;
  final bool showConnector;
  final String navigateLabel;

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).statusColors;
    final isOpen = number != null;
    final hasAddress = job.address.trim().isNotEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StopRail(
            number: number,
            badgeColor: isOpen ? employeeColor : statusColors.successContainer,
            foreground: isOpen
                ? contrastingForegroundFor(employeeColor)
                : statusColors.onSuccessContainer,
            showConnector: showConnector,
          ),
          const SizedBox(width: AppSpacing.sp12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sp12),
              child: Opacity(
                opacity: isOpen ? 1 : 0.62,
                child: AppointmentCard(
                  appointment: job,
                  employeeColor: employeeColor,
                  onTap: () => showEventDetails(context, job),
                  footer: (isOpen && hasAddress)
                      ? _NavigatePill(
                          label: navigateLabel,
                          onTap: () => AddressMapLauncher.showMapChoices(
                            context,
                            address: job.address,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopRail extends StatelessWidget {
  const _StopRail({
    required this.number,
    required this.badgeColor,
    required this.foreground,
    required this.showConnector,
  });

  final int? number;
  final Color badgeColor;
  final Color foreground;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
          child: number != null
              ? FittedBox(
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                )
              : Icon(Icons.check, size: 16, color: foreground),
        ),
        if (showConnector)
          Expanded(child: Container(width: 2, color: scheme.outlineVariant)),
      ],
    );
  }
}

class _NavigatePill extends StatelessWidget {
  const _NavigatePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.rFull),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sp12,
              vertical: AppSpacing.sp8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_outlined,
                  size: 16,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.sp4),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
