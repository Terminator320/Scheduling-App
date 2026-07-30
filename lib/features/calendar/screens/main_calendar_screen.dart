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
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
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
      _monthLabelFormat = DateFormat.yMMMM(locale);
      _lastLocale = locale;
    }

    return (
      userName: userName,
      colorMap: colorMap,
      nameMap: nameMap,
      isLoading: appointmentsAsync.isLoading,
      monthLabel: _monthLabelFormat.format(_focusedDay),
      jobLabel: context.l10n.calendar_appointmentCount(selectedEvents.length),
      today: today,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
        appBar: AppTopBar(
          title: context.l10n.common_calendar,
          compact: context.isLandscape,
          actions: _appBarActions(context, scheme),
          bottom: PreferredSize(
            // Scale the month bar's height to the user's text size, so it doesn't clip at large accessibility scales.
            preferredSize: Size.fromHeight(
              MediaQuery.textScalerOf(
                context,
              ).scale(context.isLandscape ? 22 : 28),
            ),
            child: _CalendarMonthBar(
              monthLabel: data.monthLabel,
              jobLabel: data.jobLabel,
              onPickMonth: _pickMonth,
            ),
          ),
        ),
        floatingActionButton: _addAppointmentFab(context),
        endDrawer: AppNavDrawer(
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
          userName: data.userName,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              _content(
                isLoading: data.isLoading,
                colorMap: data.colorMap,
                nameMap: data.nameMap,
                today: data.today,
              ),
              Positioned(
                bottom: AppSpacing.sp16,
                left: AppSpacing.sp16,
                child: _TodayFab(
                  visible: _showTodayButton(data.today),
                  onPressed: () => _goToToday(data.today),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _appBarActions(BuildContext context, ColorScheme scheme) => [
    _tourStep(
      TourStepId.calendarDayRoute,
      targetBorderRadius: BorderRadius.circular(AppRadius.rFull),
      child: IconButton(
        icon: Icon(Icons.alt_route_rounded, color: scheme.onPrimary),
        tooltip: context.l10n.calendar_dayRouteTitle,
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.dayRoute,
          arguments: DayRouteArgs(
            isAdmin: widget.isAdmin,
            employeeId: widget.employeeId,
          ),
        ),
      ),
    ),
    const AppHeaderPair(),
  ];

  Widget? _addAppointmentFab(BuildContext context) {
    if (!widget.isAdmin) return null;
    return _tourStep(
      TourStepId.calendarAddAppointment,
      targetBorderRadius: BorderRadius.circular(AppRadius.r16),
      child: FloatingActionButton(
        heroTag: 'addFab',
        tooltip: context.l10n.calendar_newAppointment,
        onPressed: () async {
          await showAddEventPopup(
            context,
            initialDate: _selectedDay ?? _focusedDay,
          );
        },
        child: const Icon(Icons.add),
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
  }) {
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
            child: PrimaryScrollScope(child: Column(children: [eventList])),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildCalendar(colorMap, today),
        const Divider(height: 1),
        eventList,
      ],
    );
  }
}

/// The app bar's bottom row — a tappable month label plus the selected day's appointment count.
class _CalendarMonthBar extends StatelessWidget {
  const _CalendarMonthBar({
    required this.monthLabel,
    required this.jobLabel,
    required this.onPickMonth,
  });

  final String monthLabel;
  final String jobLabel;
  final VoidCallback onPickMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onPrimary.withValues(alpha: 0.82),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        0,
        AppSpacing.sp16,
        context.isLandscape ? AppSpacing.sp4 : AppSpacing.sp8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Semantics(
              button: true,
              label: context.l10n.calendar_selectDate,
              child: GestureDetector(
                onTap: onPickMonth,
                child: Text(
                  monthLabel,
                  style: labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sp8),
          Flexible(
            child: Text(
              jobLabel,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "jump to today" FAB. It scales and fades out once today is already in view.
class _TodayFab extends StatelessWidget {
  const _TodayFab({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.75,
      duration: AppDuration.normal,
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: AppDuration.normal,
        child: IgnorePointer(
          ignoring: !visible,
          child: FloatingActionButton(
            heroTag: 'todayFab',
            tooltip: context.l10n.calendar_today,
            onPressed: onPressed,
            child: const Icon(Icons.today),
          ),
        ),
      ),
    );
  }
}
