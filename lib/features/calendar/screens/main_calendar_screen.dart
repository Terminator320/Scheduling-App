import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/fields/month_year_picker.dart';
import 'package:scheduling/features/calendar/widgets/views/app_calendar_view.dart';
import 'package:scheduling/features/calendar/widgets/views/event_list.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';
import 'package:table_calendar/table_calendar.dart';

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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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

  /// The calendar uses the "Split" layout — month grid | day agenda, details via
  /// a sheet — whenever the nav rail is showing: landscape phones AND tablets.
  /// A portrait phone keeps the simple stacked column. There is no separate
  /// tablet layout — tablets get the same Split as landscape.
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

  // Show the "jump to today" FAB whenever the visible month isn't the current
  // one. Keyed on year+month, NOT `isSameDay(_focusedDay, today)`: a month swipe
  // reports the 1st of the month as `focusedDay` (table_calendar's page base
  // day), so a day-equality check kept the FAB visible after swiping back to
  // this month even though today is right there.
  bool get _showTodayButton {
    final now = DateTime.now();
    return _focusedDay.year != now.year || _focusedDay.month != now.month;
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedDay = now;
      _selectedDay = now;
      _appointmentRange = AppointmentDateRange.visibleMonth(now);
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
  // Memoization key for _dayIndex: the appointments list last indexed.
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

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      final newRange = AppointmentDateRange.visibleMonth(focusedDay);
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        if (newRange != _appointmentRange) _appointmentRange = newRange;
      });
    }
  }

  // Error logging/surfacing for the appointments stream — fires only on the
  // data→error transition. A `.when` error branch would re-log every rebuild.
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

  // A non-admin whose role becomes 'admin' is routed to the admin calendar
  // after the current frame (guarded so it fires once).
  void _upgradeIfAdmin(String? role) {
    if (role != 'admin' || !mounted || _upgradingToAdmin) return;
    _upgradingToAdmin = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      navigateToDestination(
        context,
        AdaptiveDestination.calendar,
        isAdmin: true,
        employeeId: widget.employeeId,
      );
    });
  }

  Future<void> _pickMonth() async {
    final picked = await MonthYearPicker.show(context, _focusedDay);
    if (picked != null && mounted) _setFocusedDay(picked);
  }

  /// The appointments stream this screen renders: business-wide for an admin,
  /// only the signed-in employee's otherwise. Shared by the watch in
  /// [_prepareBuild] and the listen in [build] so both hit the same instance.
  StreamProvider<List<AppointmentRecord>> get _appointmentsProvider =>
      widget.isAdmin
      ? appointmentsInRangeProvider(_appointmentRange)
      : myAppointmentsProvider((
          employeeId: widget.employeeId,
          range: _appointmentRange,
        ));

  /// Watches the appointment/employee providers, refreshes the day-index /
  /// selected-day / locale caches, and returns just the values [build]'s widget
  /// tree renders — so `build` stays a plain tree. The `ref.listen`
  /// registrations stay at the call site in [build] where their side effects
  /// are visible.
  ({
    String userName,
    Map<String, Color> colorMap,
    Map<String, String> nameMap,
    bool isLoading,
    String monthLabel,
    String jobLabel,
  })
  _prepareBuild(BuildContext context) {
    final appointmentsAsync = ref.watch(_appointmentsProvider);
    final userName = ref.watch(currentUserNameProvider);
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);

    // Error logging/surfacing is owned by the onAsyncChange listener in build —
    // a `.when` error branch here would re-log on every rebuild.
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

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppTopBar(
        title: context.l10n.common_calendar,
        compact: context.isLandscape,
        actions: _appBarActions(context, scheme),
        bottom: PreferredSize(
          // Scale with the user's text size so the month bar's single line of
          // label text doesn't clip at large accessibility scales (1.4x+).
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
      endDrawer: SettingsDrawer.endDrawerFor(
        context,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        userName: data.userName,
      ),
      body: AdaptiveShell(
        currentDestination: AdaptiveDestination.calendar,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        userName: data.userName,
        child: SafeArea(
          child: Stack(
            children: [
              _content(
                isLoading: data.isLoading,
                colorMap: data.colorMap,
                nameMap: data.nameMap,
              ),
              Positioned(
                bottom: AppSpacing.sp16,
                left: AppSpacing.sp16,
                child: _TodayFab(
                  visible: _showTodayButton,
                  onPressed: _goToToday,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _appBarActions(BuildContext context, ColorScheme scheme) => [
    IconButton(
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
    // In landscape / on tablets the nav rail replaces the drawer.
    if (!context.isSplitLayout)
      IconButton(
        icon: Icon(Icons.menu, color: scheme.onPrimary),
        tooltip: context.l10n.calendar_openMenuTooltip,
        onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
      ),
  ];

  Widget? _addAppointmentFab(BuildContext context) {
    if (!widget.isAdmin) return null;
    return FloatingActionButton(
      heroTag: 'addFab',
      tooltip: context.l10n.calendar_newAppointment,
      onPressed: () async {
        await showAddEventPopup(
          context,
          initialDate: _selectedDay ?? _focusedDay,
        );
      },
      child: const Icon(Icons.add),
    );
  }

  AppCalendar _buildCalendar(Map<String, Color> colorMap, double rowHeight) =>
      AppCalendar(
        focusedDay: _focusedDay,
        selectedDay: _selectedDay,
        onDaySelected: _onDaySelected,
        rowHeight: rowHeight,
        eventLoader: _getEventsForDay,
        onCalendarCreated: (_) {},
        onPageChanged: _setFocusedDay,
        employeeColorMap: colorMap,
      );

  Widget _content({
    required bool isLoading,
    required Map<String, Color> colorMap,
    required Map<String, String> nameMap,
  }) {
    final eventList = EventList(
      events: _selectedEvents,
      nameMap: nameMap,
      colorMap: colorMap,
      isLoading: isLoading,
      isAdmin: widget.isAdmin,
    );

    if (_splitCalendar) {
      // Both panes scroll and are alive at once, so scope each under its own
      // PrimaryScrollController — otherwise the calendar's SingleChildScrollView
      // and the event list both attach to the tab's shared controller and the
      // Scrollbar throws (it needs one ScrollPosition per controller).
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: PrimaryScrollScope(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Size the month rows to the pane: compact in the short
                  // landscape viewport, comfortable on a tall tablet.
                  final rowHeight = ((constraints.maxHeight - 40) / 6).clamp(
                    40.0,
                    88.0,
                  );
                  return SingleChildScrollView(
                    child: _buildCalendar(colorMap, rowHeight),
                  );
                },
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the six week-rows off the *available* height, not the full
        // screen. Sizing off MediaQuery.size overshoots whenever the body is
        // shorter than the screen (keyboard open, split-screen, foldable,
        // large text scale forcing a six-week grid): the fixed-height month
        // grid would push past the body and overflow this column, starving
        // the Expanded event list. Reserve the day-of-week header (36) out of
        // the calendar's ~55% share, then clamp rows to a tappable band so the
        // event list always keeps room. Mirrors the split-calendar path above.
        final rowHeight = ((constraints.maxHeight * 0.55 - 36) / 6).clamp(
          36.0,
          56.0,
        );
        return Column(
          children: [
            _buildCalendar(colorMap, rowHeight),
            const SizedBox(height: AppSpacing.sp12),
            const Divider(),
            eventList,
          ],
        );
      },
    );
  }
}

/// The app-bar bottom row: tappable month label (opens the month picker) and
/// the selected day's appointment count.
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

/// The "jump to today" FAB — scales/fades out (and stops absorbing taps) when
/// today is already in view. Wrap in a [Positioned] inside the body stack.
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
