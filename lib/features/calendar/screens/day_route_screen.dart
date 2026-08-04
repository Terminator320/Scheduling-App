import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/adaptive/adaptive_pickers.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/launchers/route_map_launcher.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/domain/tour_steps.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/route_url_builder.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// A job is still "to drive to" — it gets a number and a spot in the route — as long as its status isn't terminal yet.
bool _isOpen(String status) => !AppointmentStatus.fromRaw(status).isTerminal;

/// Shows a day's jobs as a numbered route timeline with per-stop navigation. Admins can also pick which employee's route to view.
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
  late final _tour = TourSteps(
    const DestinationTour(PushedDestination.dayRoute),
    isAdmin: widget.isAdmin,
  );

  @override
  void initState() {
    super.initState();
    _day = DateTime.now().dateOnly;
    _selectedEmployeeId = widget.employeeId;
  }

  // Fall back to the first assignee if switching days leaves the selection empty. Non-admins always view their own jobs anyway.
  String _resolveEmployeeId(List<String> assigneeIds) {
    if (!widget.isAdmin) return widget.employeeId;
    if (assigneeIds.isEmpty) return _selectedEmployeeId;
    return assigneeIds.contains(_selectedEmployeeId)
        ? _selectedEmployeeId
        : assigneeIds.first;
  }

  // Only fire on the data→error transition — .when would otherwise re-fire this on every rebuild while the stream stays errored.
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
    // A WEEK window, not a day: `_prepareBuild` re-scopes to `_day` with
    // `sliceFor` regardless, and a per-day range would mint a new provider key
    // — and a new 15-day Firestore query — on every ◀/▶ tap.
    final range = AppointmentDateRange.forWeekBucketOf(_day);

    // Admins read the whole day's appointments so the employee picker has something to show. Employees just read their own visible jobs.
    final provider = widget.isAdmin
        ? appointmentsInRangeProvider(range)
        : myAppointmentsProvider((employeeId: widget.employeeId, range: range));
    final async = ref.watch(provider);
    ref.listen(provider, _onAppointmentsAsyncChange);

    final data = _prepareBuild(async.value ?? const <AppointmentRecord>[]);

    return FeatureTourHost(
      scope: _tour.scope,
      isAdmin: widget.isAdmin,
      stepKeys: _tour.keys,
      // Gated on the data: an ungated start would target the loading
      // skeletons and mark the screen seen against them.
      ready: async is AsyncData<List<AppointmentRecord>>,
      child: _buildScaffold(async, data),
    );
  }

  Widget _buildScaffold(
    AsyncValue<List<AppointmentRecord>> async,
    _DayRouteData data,
  ) {
    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.calendar_dayRouteTitle,
        onBack: () => Navigator.pop(context),
        compact: context.isLandscape,
        actions: const [AppHeaderPair()],
      ),
      endDrawer: AppNavDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
      bottomNavigationBar: _tour.stepIf(
        TourStepId.dayRouteNavigate,
        _routeButton(data.stops),
      ),
      // A pushed route sits above the hub tabs' scopes, so it needs its own
      // or it attaches to the root PrimaryScrollController alongside any
      // other pushed route.
      body: PrimaryScrollScope(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _tour.stepIf(TourStepId.dayRouteDaySwitcher, _daySwitcher()),
              // Absent on a day with no assignees, and for employees —
              // isTargetRendered skips the step rather than failing.
              if (widget.isAdmin && data.assigneeEntries.isNotEmpty)
                _tour.stepIf(
                  TourStepId.dayRouteEmployee,
                  _employeePicker(data.assigneeEntries, data.employeeId),
                ),
              Expanded(
                child: _tour.stepIf(
                  TourStepId.dayRouteStops,
                  _timeline(async, data.jobs, data.employeeId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Derives the render-ready slice of the day from the raw appointments:
  // filter+sort into driving order, resolve which assignee's route to show,
  // then the jobs for that assignee and their navigable stops.
  _DayRouteData _prepareBuild(List<AppointmentRecord> source) {
    // Re-scoped to `_day`: the range stream is a 14-day superset — see runsOn.
    // Slices, not records, so a continuing job carries THAT day's window.
    final daySlices =
        source
            .where((a) => !AppointmentStatus.fromRaw(a.status).isCancelled)
            .map((a) => sliceFor(a, _day))
            .nonNulls
            .toList()
          // Sort defensively to keep numbering and the route in driving order.
          ..sort((a, b) => a.windowStart.compareTo(b.windowStart));

    // Collect the distinct employees assigned that day, falling back to the denormalized names for anyone who's since been removed.
    final assigneeEntries = widget.isAdmin
        ? _assigneesWithJobs(daySlices)
        : const <MapEntry<String, String>>[];
    final employeeId = _resolveEmployeeId([
      for (final e in assigneeEntries) e.key,
    ]);

    // For admins, filter the whole-day list down to the picked assignee. The employee's own query is already scoped, so nothing more to do there.
    final jobs = widget.isAdmin
        ? daySlices
              .where((s) => s.appointment.employeeIds.contains(employeeId))
              .toList()
        : daySlices;
    final stops = jobs
        .where(
          (s) =>
              _isOpen(s.appointment.status) &&
              s.appointment.address.trim().isNotEmpty,
        )
        .map((s) => s.appointment.address)
        .toList();

    return _DayRouteData(
      assigneeEntries: assigneeEntries,
      employeeId: employeeId,
      jobs: jobs,
      stops: stops,
    );
  }

  // Distinct id → display name for every employee assigned to a job that day.
  List<MapEntry<String, String>> _assigneesWithJobs(
    List<AppointmentDaySlice> daySlices,
  ) {
    final nameMap = ref.watch(employeeNameMapProvider);
    final byId = <String, String>{};
    for (final slice in daySlices) {
      final a = slice.appointment;
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

  Future<void> _pickDay() async {
    final now = DateTime.now().dateOnly;
    final picked = await showAdaptiveDatePicker(
      context,
      initialDate: _day,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _day = picked.dateOnly);
    }
  }

  Widget _daySwitcher() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // The one day-header formatter, memoized per locale — the calendar agenda,
    // history day groups and dashboard hero all render through it too.
    final label = DateUtilsHelper.formatDayHeader(_day);
    final isToday = _day == DateTime.now().dateOnly;
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
            onPressed: () => setState(() => _day = addCalendarDays(_day, -1)),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.r8),
              onTap: _pickDay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sp8),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!isToday)
            IconButton(
              icon: const Icon(Icons.today_outlined),
              tooltip: l10n.calendar_today,
              onPressed: () => setState(() => _day = DateTime.now().dateOnly),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.calendar_dayRouteNextDay,
            onPressed: () => setState(() => _day = addCalendarDays(_day, 1)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickEmployee(
    List<MapEntry<String, String>> assignees,
  ) async {
    final picked = await showAdaptiveActionSheet<String>(
      context,
      title: context.l10n.calendar_dayRouteEmployeeLabel,
      actions: [
        for (final e in assignees)
          AdaptiveSheetAction(value: e.key, label: e.value),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _selectedEmployeeId = picked);
    }
  }

  Widget _employeePicker(
    List<MapEntry<String, String>> assignees,
    String value,
  ) {
    final theme = Theme.of(context);
    final currentName = assignees
        .firstWhere((e) => e.key == value, orElse: () => assignees.first)
        .value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        0,
        AppSpacing.sp16,
        AppSpacing.sp8,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        onTap: () => _pickEmployee(assignees),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: context.l10n.calendar_dayRouteEmployeeLabel,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sp16,
              vertical: AppSpacing.sp12,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(currentName, overflow: TextOverflow.ellipsis),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
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
    List<AppointmentDaySlice> jobs,
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
      numbers.add(_isOpen(j.appointment.status) ? ++open : null);
    }
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);
    final empColor =
        colorMap[employeeId] ?? Theme.of(context).colorScheme.primary;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        AppSpacing.sp8,
        AppSpacing.sp16,
        AppSpacing.sp16,
      ),
      itemCount: jobs.length,
      itemBuilder: (context, i) => _StopTile(
        slice: jobs[i],
        number: numbers[i],
        employeeColor: empColor,
        crew: crewFor(
          jobs[i].appointment,
          colorMap: colorMap,
          nameMap: nameMap,
        ),
        showConnector: i < jobs.length - 1,
        navigateLabel: l10n.calendar_dayRouteNavigate,
        isAdmin: widget.isAdmin,
      ),
    );
  }
}

/// The render-ready slice of a day computed once per `build` by `_prepareBuild`.
class _DayRouteData {
  const _DayRouteData({
    required this.assigneeEntries,
    required this.employeeId,
    required this.jobs,
    required this.stops,
  });

  final List<MapEntry<String, String>> assigneeEntries;
  final String employeeId;
  final List<AppointmentDaySlice> jobs;
  final List<String> stops;
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.slice,
    required this.number,
    required this.employeeColor,
    required this.crew,
    required this.showConnector,
    required this.navigateLabel,
    required this.isAdmin,
  });

  /// This stop as it runs on the day being shown — day 3 of a run carries that
  /// day's own window, not the run's first morning.
  final AppointmentDaySlice slice;
  final int? number;

  /// The route's own employee — the rail badge, not the card's crew bar.
  final Color employeeColor;
  final List<AppointmentCrew> crew;
  final bool showConnector;
  final String navigateLabel;

  /// Gates the admin-only actions on the sheet this stop's card opens.
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).statusColors;
    final isOpen = number != null;
    final job = slice.appointment;
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
                  crew: crew,
                  slice: slice,
                  onTap: () =>
                      showEventDetails(context, job, showActions: isAdmin),
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
