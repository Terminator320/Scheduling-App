import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/app/photo_upload_failure_listener.dart';
import 'package:scheduling/core/app/role_upgrade_listener.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/collapse_state.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/fields/month_year_picker.dart';
import 'package:scheduling/features/calendar/widgets/views/agenda_sliver_list.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_header_block.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_grid.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_pager.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_week_strip.dart';
import 'package:scheduling/features/calendar/widgets/views/collapse_handle.dart';
import 'package:scheduling/features/calendar/widgets/views/event_list.dart';
import 'package:scheduling/features/calendar/widgets/views/today_pill.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/domain/tour_steps.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

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
  final _agendaController = ScrollController();
  final _collapse = CalendarCollapse();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late AppointmentDateRange _appointmentRange;

  /// Captured so dispose can clear without touching `ref`.
  OpenCalendarRange? _openRange;
  late DateFormat _monthLabelFormat;
  late DateFormat _monthShortLabelFormat;
  late DateFormat _yearLabelFormat;
  String _lastLocale = '';

  late final _tour = TourSteps(
    const DestinationTour(HubTab.calendar),
    isAdmin: widget.isAdmin,
  );

  /// Uses the "Split" layout (month grid | day agenda) when the nav rail shows.
  bool get _splitCalendar => context.isSplitLayout;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _appointmentRange = AppointmentDateRange.forCalendar(
      focusedDay: _focusedDay,
      selectedDay: _focusedDay,
    );
    if (widget.isAdmin) {
      _openRange = ref.read(openCalendarRangeProvider.notifier);
    }
    // Publish after build so Riverpod accepts the provider write.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishRange();
    });
  }

  @override
  void dispose() {
    _agendaController.dispose();
    // Clear only the range this screen still owns.
    _openRange?.clearIfHolding(this);
    super.dispose();
  }

  /// Publishes the open calendar range for admin child surfaces.
  void _publishRange() => _openRange?.publish(this, _appointmentRange);

  void _onCollapseDrag(double dy) {
    if (_collapse.onDragDelta(dy)) setState(() {});
  }

  void _toggleCollapse() {
    _collapse.toggle();
    setState(() {});
  }

  // Show Today when either the selected day or focused month differs.
  bool _showTodayButton(DateTime today) =>
      !isSameDate(_selectedDay ?? _focusedDay, today) ||
      !isInMonth(today, _focusedDay);

  void _goToToday(DateTime today) {
    setState(() {
      _focusedDay = today;
      _selectedDay = today;
      _appointmentRange = AppointmentDateRange.forCalendar(
        focusedDay: today,
        selectedDay: today,
      );
    });
    _publishRange();
  }

  /// Moves focus and selection to the given month/day.
  void _setFocusedDay(DateTime day) {
    final newRange = AppointmentDateRange.forCalendar(
      focusedDay: day,
      selectedDay: day,
    );
    setState(() {
      _focusedDay = day;
      _selectedDay = day;
      if (newRange != _appointmentRange) _appointmentRange = newRange;
    });
    _publishRange();
  }

  /// Pages the collapsed week strip by one week.
  void _pageWeek(int direction) {
    final from = _selectedDay ?? _focusedDay;
    final weekStart = CalendarMonthGrid.weekStartOf(context);
    final target = DateTime(from.year, from.month, from.day + 7 * direction);
    _onDaySelected(weekOf(target, weekStart: weekStart).first);
  }

  Map<DateTime, List<AppointmentDaySlice>>? _dayIndex;
  // Tracks the source list used for _dayIndex.
  List<AppointmentRecord>? _indexedAppointments;

  /// Rebuilds [_dayIndex] only for a new source list.
  void _refreshDayIndex(List<AppointmentRecord> source) {
    if (identical(source, _indexedAppointments)) return;
    _indexedAppointments = source;
    _dayIndex = expandToDays(
      source,
      _appointmentRange,
      onSpanClamped: (appointment, actualDays) => ref
          .read(loggerProvider)
          .warn(
            'APPT-RANGE appointment ${appointment.id} spans $actualDays days, '
            'past the $maxAppointmentSpanDays-day cap - showing the first '
            '$maxAppointmentSpanDays',
          ),
    );
  }

  List<AppointmentDaySlice> _getEventsForDay(DateTime day) =>
      _dayIndex?[day.dateOnly] ?? const <AppointmentDaySlice>[];

  /// Records running on [day], used for crew dots.
  Iterable<AppointmentRecord> _appointmentsOn(DateTime day) =>
      _getEventsForDay(day).map((slice) => slice.appointment);

  void _onDaySelected(DateTime selectedDay) {
    if (isSameDate(_selectedDay ?? _focusedDay, selectedDay)) return;
    final newRange = AppointmentDateRange.forCalendar(
      focusedDay: selectedDay,
      selectedDay: selectedDay,
    );
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = selectedDay;
      if (newRange != _appointmentRange) _appointmentRange = newRange;
    });
    _publishRange();
  }

  // Report only the first data-to-error transition.
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
            error: next.error ?? Exception('unknown'),
          ),
        );
  }

  Future<void> _pickMonth() async {
    final picked = await MonthYearPicker.show(context, _focusedDay);
    if (picked != null && mounted) _setFocusedDay(picked);
  }

  /// Appointments stream for the current user scope.
  StreamProvider<List<AppointmentRecord>> get _appointmentsProvider =>
      widget.isAdmin
      ? appointmentsInRangeProvider(_appointmentRange)
      : myAppointmentsProvider((
          employeeId: widget.employeeId,
          range: _appointmentRange,
        ));

  /// Prepares the provider values build renders.
  ({
    String userName,
    Map<String, Color> colorMap,
    Map<String, String> nameMap,
    bool isLoading,
    String monthLabel,
    String monthLabelShort,
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
    // Watch currentDayProvider so midnight updates the UI.
    final today = ref.watch(currentDayProvider);

    // Error logging is owned by the onAsyncChange listener in build.
    final visibleAppointments =
        appointmentsAsync.value ?? const <AppointmentRecord>[];

    _refreshDayIndex(visibleAppointments);

    final selectedDay = _selectedDay ?? _focusedDay;
    final selectedEvents = _getEventsForDay(selectedDay);

    final locale = Localizations.localeOf(context).toString();
    if (locale != _lastLocale) {
      _monthLabelFormat = DateFormat.MMMM(locale);
      _monthShortLabelFormat = DateFormat.MMM(locale);
      _yearLabelFormat = DateFormat.y(locale);
      _lastLocale = locale;
    }

    return (
      userName: userName,
      colorMap: colorMap,
      nameMap: nameMap,
      isLoading: appointmentsAsync.isLoading,
      // Header decides which month label fits.
      monthLabel: _monthLabelFormat.format(_focusedDay),
      monthLabelShort: _monthShortLabelFormat.format(_focusedDay),
      yearLabel: _yearLabelFormat.format(_focusedDay),
      dayTitle: DateUtilsHelper.formatDayHeader(selectedDay),
      jobLabel: _jobLabel(context, selectedEvents),
      today: today,
    );
  }

  /// Agenda count label for work and done totals.
  static String _jobLabel(
    BuildContext context,
    List<AppointmentDaySlice> events,
  ) {
    final l10n = context.l10n;
    final jobs = events
        .where((slice) => countsAsWork(slice.appointment))
        .toList();
    final total = l10n.calendar_jobsCount(jobs.length);
    final done = jobs.where((slice) => slice.appointment.isClosed).length;
    return done == 0 ? total : '$total · ${l10n.calendar_jobsDoneCount(done)}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_appointmentsProvider, _onAppointmentsAsyncChange);

    final data = _prepareBuild(context);

    // Session listeners are hosted at the calendar shell.
    return RoleUpgradeListener(
      employeeId: widget.employeeId,
      isAdmin: widget.isAdmin,
      child: PhotoUploadFailureListener(
        showActions: widget.isAdmin,
        child: FeatureTourHost(
          scope: _tour.scope,
          isAdmin: widget.isAdmin,
          ready: !data.isLoading,
          stepKeys: _tour.keys,
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
                  monthLabelShort: data.monthLabelShort,
                  yearLabel: data.yearLabel,
                  onPickMonth: _pickMonth,
                  routeButton: _dayRouteButton(context),
                  weekStrip: _weekStrip(data.today, data.colorMap),
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
                          child: TodayPill(
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
        ),
      ),
    );
  }

  /// Collapsed week strip, hidden in split layout.
  Widget? _weekStrip(DateTime today, Map<String, Color> colorMap) {
    if (_splitCalendar || !_collapse.isCollapsed) return null;
    final selectedDay = _selectedDay ?? _focusedDay;
    // Horizontal swipes page weeks.
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity == 0) return;
        _pageWeek(velocity < 0 ? 1 : -1);
      },
      child: CalendarWeekStrip(
        weekDays: weekOf(
          selectedDay,
          weekStart: CalendarMonthGrid.weekStartOf(context),
        ),
        selectedDay: selectedDay,
        today: today,
        onDaySelected: _onDaySelected,
        dotColorsFor: (day) =>
            dayJobDotColors(_appointmentsOn(day), colorMap, max: 1),
      ),
    );
  }

  /// Day-route control owned by this screen's tour.
  Widget _dayRouteButton(BuildContext context) {
    final theme = Theme.of(context);
    return _tour.step(
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
    return _tour.step(
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
      _tour.step(
        TourStepId.calendarGrid,
        child: CalendarMonthPager(
          month: _focusedDay,
          selectedDay: _selectedDay ?? _focusedDay,
          today: today,
          onDaySelected: _onDaySelected,
          onMonthChanged: _setFocusedDay,
          dotColorsFor: (day) =>
              dayJobDotColors(_appointmentsOn(day), colorMap),
          // Semantics count the same jobs as the dots.
          countFor: (day) => dottedJobsOn(_appointmentsOn(day)).length,
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
    final events = _getEventsForDay(_selectedDay ?? _focusedDay);
    // The header is the stable tour target.
    final agendaHeader = _tour.step(
      TourStepId.calendarDayList,
      child: AgendaHeader(dayTitle: dayTitle, jobLabel: jobLabel),
    );

    if (_splitCalendar) {
      return _splitContent(
        events: events,
        agendaHeader: agendaHeader,
        isLoading: isLoading,
        colorMap: colorMap,
        nameMap: nameMap,
        today: today,
      );
    }

    return _portraitContent(
      events: events,
      agendaHeader: agendaHeader,
      isLoading: isLoading,
      colorMap: colorMap,
      nameMap: nameMap,
      today: today,
    );
  }

  /// Landscape phones and tablets: month grid | day agenda, side by side.
  Widget _splitContent({
    required List<AppointmentDaySlice> events,
    required Widget agendaHeader,
    required bool isLoading,
    required Map<String, Color> colorMap,
    required Map<String, String> nameMap,
    required DateTime today,
  }) {
    // Give each split pane its own primary scroll controller.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 11,
          // Let the grid scroll instead of clipping at large text sizes.
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
            child: Column(
              children: [
                agendaHeader,
                EventList(
                  events: events,
                  nameMap: nameMap,
                  colorMap: colorMap,
                  isLoading: isLoading,
                  isAdmin: widget.isAdmin,
                  // Reserve room for this pane's floating controls.
                  bottomClearance: kAgendaFloatingControlsClearance,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Portrait layout with fixed grid and scrolling agenda.
  Widget _portraitContent({
    required List<AppointmentDaySlice> events,
    required Widget agendaHeader,
    required bool isLoading,
    required Map<String, Color> colorMap,
    required Map<String, String> nameMap,
    required DateTime today,
  }) {
    // The agenda scrolls independently from the fixed grid.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The grid viewport is overflow protection, not user scrolling.
        if (!_collapse.isCollapsed)
          Flexible(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: _buildCalendar(colorMap, today),
            ),
          ),
        // The section divider is also the collapse control.
        _tour.step(
          TourStepId.calendarCollapse,
          child: CollapseHandle(
            isCollapsed: _collapse.isCollapsed,
            onDrag: _onCollapseDrag,
            onDragEnd: _collapse.endDrag,
            onToggle: _toggleCollapse,
          ),
        ),
        agendaHeader,
        Expanded(
          child: CustomScrollView(
            controller: _agendaController,
            // Use a private controller because the grid is another scrollable.
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              AgendaSliverList(
                events: events,
                nameMap: nameMap,
                colorMap: colorMap,
                isLoading: isLoading,
                isAdmin: widget.isAdmin,
                // The FAB and the Today pill float over this list, so the last
                // job of the day needs somewhere to scroll clear of them.
                bottomClearance: kAgendaFloatingControlsClearance,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
