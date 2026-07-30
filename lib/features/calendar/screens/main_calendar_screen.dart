import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/fields/month_year_picker.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_header_block.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_pager.dart';
import 'package:scheduling/features/calendar/widgets/views/event_list.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';

class MainCalendar extends ConsumerStatefulWidget {
  const MainCalendar({
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final bool isAdmin;
  final String employeeId;

  @override
  ConsumerState<MainCalendar> createState() => _MainCalendarState();
}

class _MainCalendarState extends ConsumerState<MainCalendar> {
  final ValueNotifier<List<AppointmentRecord>> _selectedEvents = ValueNotifier(
    [],
  );

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late AppointmentDateRange _appointmentRange;
  PhotoUploadNotifier? _uploadNotifier;
  bool _upgradingToAdmin = false;
  late DateFormat _monthLabelFormat;
  late DateFormat _yearLabelFormat;
  String _lastLocale = '';

  late final List<TourStepId> _tourSteps = tourStepsFor(
    HubTab.calendar,
    isAdmin: widget.isAdmin,
  );
  late final Map<TourStepId, GlobalKey> _tourKeys = {
    for (final id in _tourSteps) id: GlobalKey(),
  };

  /// Uses the "Split" layout (month grid | day agenda) when the nav rail shows.
  bool get _splitCalendar => context.isSplitLayout;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _appointmentRange = AppointmentDateRange.visibleMonth(_focusedDay);
    _initStreams();
  }

  void _initStreams() {
    _uploadNotifier = ref.read(photoUploadNotifierProvider);
    _uploadNotifier?.latestFailure.addListener(_onUploadFailure);
  }

  @override
  void dispose() {
    _uploadNotifier?.latestFailure.removeListener(_onUploadFailure);
    _selectedEvents.dispose();
    super.dispose();
  }

  void _onUploadFailure() {
    final failure = _uploadNotifier?.latestFailure.value;
    if (failure == null || !mounted) return;
    final appointmentId = failure.appointmentId;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      errorSnackBar(
        context,
        context.l10n.calendar_photoUploadFailedSnackbar,
        action: SnackBarAction(
          label: context.l10n.calendar_open,
          textColor: scheme.onErrorContainer,
          onPressed: () async {
            final appointment = await ref
                .read(appointmentsRepositoryProvider)
                .getAppointmentById(appointmentId);
            if (!mounted || appointment == null) return;
            await showEventDetails(
              context,
              appointment,
              showActions: widget.isAdmin,
            );
          },
        ),
      ),
    );
  }

  // Show the "today" control whenever the day on screen isn't today — not just
  // when the visible month differs, which left it hidden while the user was
  // reading another day of the current month (owner call, 2026-07-30). [today]
  // comes from currentDayProvider, so it re-derives across midnight.
  bool _showTodayButton(DateTime today) =>
      !isSameDate(_selectedDay ?? _focusedDay, today);

  void _goToToday(DateTime today) {
    setState(() {
      _focusedDay = today;
      _selectedDay = today;
      _appointmentRange = AppointmentDateRange.visibleMonth(today);
    });
  }

  void _setFocusedDay(DateTime day) {
    final newRange = AppointmentDateRange.visibleMonth(day);
    setState(() {
      _focusedDay = day;
      if (newRange != _appointmentRange) _appointmentRange = newRange;
    });
  }

  Map<DateTime, List<AppointmentRecord>>? _dayIndex;
  // Remembers which appointments list _dayIndex was last built from, so we know when it needs rebuilding.
  List<AppointmentRecord>? _indexedAppointments;

  /// Rebuilds [_dayIndex] only when [source] is a different list instance than
  /// the one last indexed — the index is otherwise recomputed every rebuild.
  void _refreshDayIndex(List<AppointmentRecord> source) {
    if (identical(source, _indexedAppointments)) return;
    _indexedAppointments = source;
    _dayIndex = _buildDayIndex(source);
  }

  Map<DateTime, List<AppointmentRecord>> _buildDayIndex(
    List<AppointmentRecord> source,
  ) {
    final index = <DateTime, List<AppointmentRecord>>{};
    for (final app in source) {
      final key = app.startTime.dateOnly;
      (index[key] ??= <AppointmentRecord>[]).add(app);
    }
    for (final list in index.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return index;
  }

  List<AppointmentRecord> _getEventsForDay(DateTime day) {
    final key = day.dateOnly;
    return _dayIndex?[key] ?? const <AppointmentRecord>[];
  }

  void _onDaySelected(DateTime selectedDay) {
    if (isSameDate(_selectedDay ?? _focusedDay, selectedDay)) return;
    final newRange = AppointmentDateRange.visibleMonth(selectedDay);
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = selectedDay;
      if (newRange != _appointmentRange) _appointmentRange = newRange;
    });
  }

  // Only log on the data→error transition — .when would otherwise fire this on every rebuild while the stream stays errored.
  void _onAppointmentsAsyncChange(
    AsyncValue<List<AppointmentRecord>>? previous,
    AsyncValue<List<AppointmentRecord>> next,
  ) {
    if (next is! AsyncError || previous is AsyncError) return;
    ref
        .read(loggerProvider)
        .warn(
          'APPT-LOAD appointments stream error',
          next.error,
          next.stackTrace,
        );
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

  // If a non-admin gets upgraded to 'admin', route them to the admin calendar after this frame. The flag just guards against firing more than once.
  void _upgradeIfAdmin(String? role) {
    if (role != 'admin' || !mounted || _upgradingToAdmin) return;
    _upgradingToAdmin = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      navigateToDestination(
        context,
        HubTab.calendar,
        isAdmin: true,
        employeeId: widget.employeeId,
      );
    });
  }

  Future<void> _pickMonth() async {
    final picked = await MonthYearPicker.show(context, _focusedDay);
    if (picked != null && mounted) _setFocusedDay(picked);
  }

  Widget _tourStep(
    TourStepId id, {
    required Widget child,
    BorderRadius? targetBorderRadius,
  }) => TourShowcase(
    showcaseKey: _tourKeys[id]!,
    destination: HubTab.calendar,
    id: id,
    index: _tourSteps.indexOf(id),
    count: _tourSteps.length,
    targetBorderRadius: targetBorderRadius,
    child: child,
  );

  /// The appointments stream this screen renders — the whole business for admins, just their own jobs for employees.
  StreamProvider<List<AppointmentRecord>> get _appointmentsProvider =>
      widget.isAdmin
      ? appointmentsInRangeProvider(_appointmentRange)
      : myAppointmentsProvider((
          employeeId: widget.employeeId,
          range: _appointmentRange,
        ));

  /// Watches the relevant providers, refreshes the caches, and returns only the values [build] actually renders.
  ({
    String userName,
    Map<String, Color> colorMap,
    Map<String, String> nameMap,
    bool isLoading,
    String monthLabel,
    String yearLabel,
    String dayTitle,
    String jobLabel,
    DateTime today,
  })
  _prepareBuild(BuildContext context) {
    final appointmentsAsync = ref.watch(_appointmentsProvider);
    final userName = ref.watch(currentUserNameProvider);
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);
    // Watched, not DateTime.now(): the appointments stream only re-emits on a
    // write, so an app left open across midnight would keep circling yesterday.
    final today = ref.watch(currentDayProvider);

    // Error logging is owned by the onAsyncChange listener in build.
    final visibleAppointments =
        appointmentsAsync.value ?? const <AppointmentRecord>[];

    _refreshDayIndex(visibleAppointments);

    final selectedDay = _selectedDay ?? _focusedDay;
    final selectedEvents = _getEventsForDay(selectedDay);
    _selectedEvents.value = selectedEvents;

    final locale = Localizations.localeOf(context).toString();
    if (locale != _lastLocale) {
      _monthLabelFormat = DateFormat.MMMM(locale);
      _yearLabelFormat = DateFormat.y(locale);
      _lastLocale = locale;
    }

    return (
      userName: userName,
      colorMap: colorMap,
      nameMap: nameMap,
      isLoading: appointmentsAsync.isLoading,
      monthLabel: _monthLabelFormat.format(_focusedDay),
      yearLabel: _yearLabelFormat.format(_focusedDay),
      dayTitle: DateUtilsHelper.formatDayHeader(selectedDay),
      jobLabel: context.l10n.calendar_jobsCount(selectedEvents.length),
      today: today,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_appointmentsProvider, _onAppointmentsAsyncChange);
    if (!widget.isAdmin) {
      ref.listen<AsyncValue<String>>(
        userRoleProvider,
        (_, next) => _upgradeIfAdmin(next.value),
      );
      _upgradeIfAdmin(ref.read(userRoleProvider).value);
    }

    final data = _prepareBuild(context);

    return FeatureTourHost(
      destination: HubTab.calendar,
      isAdmin: widget.isAdmin,
      ready: !data.isLoading,
      stepKeys: _tourKeys,
      child: Scaffold(
        floatingActionButton: _addAppointmentFab(context),
        endDrawer: AppNavDrawer(
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
          userName: data.userName,
        ),
        body: Column(
          children: [
            CalendarHeaderBlock(
              monthLabel: data.monthLabel,
              yearLabel: data.yearLabel,
              onPickMonth: _pickMonth,
              routeButton: _dayRouteButton(context),
            ),
            Expanded(
              // The header block reserves the status bar itself.
              child: SafeArea(
                top: false,
                child: Stack(
                  children: [
                    _content(
                      isLoading: data.isLoading,
                      colorMap: data.colorMap,
                      nameMap: data.nameMap,
                      today: data.today,
                      dayTitle: data.dayTitle,
                      jobLabel: data.jobLabel,
                    ),
                    Positioned(
                      bottom: AppSpacing.sp16,
                      left: AppSpacing.sp16,
                      child: _TodayPill(
                        visible: _showTodayButton(data.today),
                        onPressed: () => _goToToday(data.today),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The Day-route control. Kept on the screen rather than inside the header
  /// block because it is a feature-tour target this screen owns.
  Widget _dayRouteButton(BuildContext context) {
    final theme = Theme.of(context);
    return _tourStep(
      TourStepId.calendarDayRoute,
      targetBorderRadius: BorderRadius.circular(AppRadius.rIcon),
      child: Tooltip(
        message: context.l10n.calendar_dayRouteTitle,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Material(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.rIcon),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.dayRoute,
                  arguments: DayRouteArgs(
                    isAdmin: widget.isAdmin,
                    employeeId: widget.employeeId,
                  ),
                ),
                highlightColor: theme.palette.blueTintPressed,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.alt_route_rounded,
                    size: 19,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _addAppointmentFab(BuildContext context) {
    if (!widget.isAdmin) return null;
    return _tourStep(
      TourStepId.calendarAddAppointment,
      targetBorderRadius: BorderRadius.circular(AppRadius.rFab),
      child: SizedBox(
        width: 58,
        height: 58,
        child: FloatingActionButton(
          heroTag: 'addFab',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.rFab),
          ),
          tooltip: context.l10n.calendar_newAppointment,
          onPressed: () async {
            await showAddEventPopup(
              context,
              initialDate: _selectedDay ?? _focusedDay,
            );
          },
          child: const Icon(Icons.add, size: 26),
        ),
      ),
    );
  }

  Widget _buildCalendar(Map<String, Color> colorMap, DateTime today) =>
      _tourStep(
        TourStepId.calendarGrid,
        child: CalendarMonthPager(
          month: _focusedDay,
          selectedDay: _selectedDay ?? _focusedDay,
          today: today,
          onDaySelected: _onDaySelected,
          onMonthChanged: _setFocusedDay,
          dotColorsFor: (day) => dayCrewColors(_getEventsForDay(day), colorMap),
          countFor: (day) => _getEventsForDay(day).length,
        ),
      );

  Widget _content({
    required bool isLoading,
    required Map<String, Color> colorMap,
    required Map<String, String> nameMap,
    required DateTime today,
    required String dayTitle,
    required String jobLabel,
  }) {
    final agendaHeader = _AgendaHeader(dayTitle: dayTitle, jobLabel: jobLabel);
    final eventList = _tourStep(
      TourStepId.calendarDayList,
      child: EventList(
        events: _selectedEvents,
        nameMap: nameMap,
        colorMap: colorMap,
        isLoading: isLoading,
        isAdmin: widget.isAdmin,
      ),
    );

    if (_splitCalendar) {
      // Scope each pane under its own PrimaryScrollController or they'll share the tab's controller.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            // The grid derives its own height from the scaled day number, so
            // the pane scrolls rather than clipping at large text sizes.
            child: PrimaryScrollScope(
              child: SingleChildScrollView(
                child: _buildCalendar(colorMap, today),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // EventList already returns an Expanded, so wrap it in a Flex.
          Expanded(
            flex: 9,
            child: PrimaryScrollScope(
              child: Column(children: [agendaHeader, eventList]),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildCalendar(colorMap, today),
        const Divider(height: 1),
        agendaHeader,
        eventList,
      ],
    );
  }
}

/// The agenda's own header — the selected day's title and a mono job count.
class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({required this.dayTitle, required this.jobLabel});

  final String dayTitle;
  final String jobLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: AppSpacing.sp8),
          Text(jobLabel, style: theme.monoType.data),
        ],
      ),
    );
  }
}

/// The "jump to today" pill. It scales and fades out once today is already in
/// view, staying mounted so the transition is animated both ways.
class _TodayPill extends StatelessWidget {
  const _TodayPill({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instant = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(AppRadius.rFull);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.85,
        duration: instant ? Duration.zero : AppMotion.popIn,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: instant ? Duration.zero : AppMotion.popIn,
          child: Tooltip(
            message: context.l10n.calendar_today,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: theme.cardStyle.pillShadow,
              ),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sp16,
                        vertical: 11,
                      ),
                      child: Center(
                        child: Text(
                          context.l10n.calendar_today,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.palette.primaryAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
