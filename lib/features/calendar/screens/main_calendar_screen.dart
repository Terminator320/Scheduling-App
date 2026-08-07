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
import 'package:scheduling/features/calendar/widgets/views/event_list.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/domain/tour_steps.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
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
  final _agendaController = ScrollController();
  final _collapse = CalendarCollapse();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late AppointmentDateRange _appointmentRange;
  PhotoUploadNotifier? _uploadNotifier;
  bool _upgradingToAdmin = false;
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
    _initStreams();
  }

  void _initStreams() {
    _uploadNotifier = ref.read(photoUploadNotifierProvider);
    _uploadNotifier?.latestFailure.addListener(_onUploadFailure);
  }

  @override
  void dispose() {
    _uploadNotifier?.latestFailure.removeListener(_onUploadFailure);
    _agendaController.dispose();
    super.dispose();
  }

  void _onCollapseDrag(double dy) {
    if (_collapse.onDragDelta(dy)) setState(() {});
  }

  void _toggleCollapse() {
    _collapse.toggle();
    setState(() {});
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
  //
  // The month test is belt-and-braces: every paging path also selects the day
  // it lands on, so the date test already covers a swipe away from today — but
  // it keeps the pill honest for any future path that moves the grid alone.
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
  }

  /// Paging to another month (by swipe or from the month picker) lands on that
  /// month's first day and selects it, so the agenda below always describes the
  /// grid above — [day] is already the 1st from both callers. Leaving the old
  /// selection behind showed a day the grid wasn't even highlighting.
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
  }

  /// Swiping the collapsed week strip moves one week and selects that week's
  /// first day — the strip's analogue of paging the month grid.
  void _pageWeek(int direction) {
    final from = _selectedDay ?? _focusedDay;
    final weekStart = CalendarMonthGrid.weekStartOf(context);
    final target = DateTime(from.year, from.month, from.day + 7 * direction);
    _onDaySelected(weekOf(target, weekStart: weekStart).first);
  }

  Map<DateTime, List<AppointmentDaySlice>>? _dayIndex;
  // Remembers which appointments list _dayIndex was last built from, so we
  // know when it needs rebuilding.
  List<AppointmentRecord>? _indexedAppointments;

  /// Rebuilds [_dayIndex] only when [source] is a different list instance than
  /// the one last indexed — the index is otherwise recomputed every rebuild.
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
            'past the $maxAppointmentSpanDays-day cap — showing the first '
            '$maxAppointmentSpanDays',
          ),
    );
  }

  List<AppointmentDaySlice> _getEventsForDay(DateTime day) =>
      _dayIndex?[day.dateOnly] ?? const <AppointmentDaySlice>[];

  /// The records running on [day], for the crew dots — lazy, since the grid
  /// asks once per cell on every rebuild.
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
    // Watched, not DateTime.now(): the appointments stream only re-emits on a
    // write, so an app left open across midnight would keep circling yesterday.
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
      // Both forms go to the header, which measures the row and picks — a
      // text-scale threshold can't know how wide "September" is in this
      // locale on this device.
      monthLabel: _monthLabelFormat.format(_focusedDay),
      monthLabelShort: _monthShortLabelFormat.format(_focusedDay),
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

  /// The collapsed week strip, or null while the month grid is on screen.
  /// Collapse is portrait-only: the split layout's month pane has no room for a
  /// rising strip and scrolls its two panes independently.
  Widget? _weekStrip(DateTime today, Map<String, Color> colorMap) {
    if (_splitCalendar || !_collapse.isCollapsed) return null;
    final selectedDay = _selectedDay ?? _focusedDay;
    // Swipe the strip to page weeks, mirroring the month grid's pager. The
    // taps inside still win — a horizontal drag recognizer doesn't claim them.
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

  /// The Day-route control. Kept on the screen rather than inside the header
  /// block because it is a feature-tour target this screen owns.
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
    final events = _getEventsForDay(_selectedDay ?? _focusedDay);
    // The header, not the list, carries the tour step: a showcase target must
    // be a box widget and the portrait agenda is a sliver.
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
            child: Column(
              children: [
                agendaHeader,
                EventList(
                  events: events,
                  nameMap: nameMap,
                  colorMap: colorMap,
                  isLoading: isLoading,
                  isAdmin: widget.isAdmin,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Portrait: TWO scroll areas — the grid is fixed above the agenda, so
  /// reading down the day never moves the calendar.
  Widget _portraitContent({
    required List<AppointmentDaySlice> events,
    required Widget agendaHeader,
    required bool isLoading,
    required Map<String, Color> colorMap,
    required Map<String, String> nameMap,
    required DateTime today,
  }) {
    // Portrait: the grid is FIXED above the agenda, and the jobs get their own
    // viewport (owner call, 2026-07-31). Collapsing is then a deliberate drag
    // on the jobs section rather than something that happens while reading down
    // the day — and once collapsed, scrolling the jobs never moves the grid
    // again. The old shared-viewport version needed a derived spacer to hold
    // the extent the grid vacated; with two viewports there is no vacated
    // extent to hold.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The grid does NOT scroll (owner call, 2026-07-31) — the handle below
        // is the only way to move it, so a stray drag on the month can't slide
        // it under the header. `NeverScrollableScrollPhysics` keeps the
        // viewport purely as overflow protection: `Flexible` lets the grid
        // yield instead of running the column past the bottom on a small phone
        // at a large text scale. At normal heights it shrink-wraps and this is
        // inert. Don't swap the physics back in to "fix" a clipped month —
        // that would restore the scroll the owner asked to remove.
        if (!_collapse.isCollapsed)
          Flexible(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: _buildCalendar(colorMap, today),
            ),
          ),
        // The line between the two sections IS the collapse control: drag it
        // up to fold the grid into the header's week strip, down to bring it
        // back. It stays put when collapsed so there is something to pull.
        _tour.step(
          TourStepId.calendarCollapse,
          child: _CollapseHandle(
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
            // Its own controller, not the primary one: the grid above is a
            // second scrollable on this route, and the app-wide Scrollbar
            // rejects two positions on one controller.
            //
            // Bouncing and always-scrollable so a day with one job still gives
            // under the finger — collapse is driven by the handle, not by this
            // list, so the bounce is feel alone.
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The divider between the month grid and the day's jobs, doubling as the
/// grab handle that collapses the grid. Painted as the same hairline the rest
/// of the screen uses, inside a 20px tall target with a short grip so it reads
/// as draggable; it is also a button, since a 24px drag is not a gesture
/// everyone can make.
class _CollapseHandle extends StatelessWidget {
  const _CollapseHandle({
    required this.isCollapsed,
    required this.onDrag,
    required this.onDragEnd,
    required this.onToggle,
  });

  final bool isCollapsed;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isCollapsed
        ? context.l10n.calendar_showCalendar
        : context.l10n.calendar_hideCalendar;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
          onVerticalDragEnd: (_) => onDragEnd(),
          onVerticalDragCancel: onDragEnd,
          onTap: onToggle,
          child: SizedBox(
            height: 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.palette.textFaint,
                    borderRadius: BorderRadius.circular(AppRadius.rFull),
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
