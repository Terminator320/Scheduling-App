import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/app_calendar_view.dart';
import 'package:scheduling/features/calendar/widgets/event_list.dart';
import 'package:scheduling/features/calendar/widgets/month_year_picker.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/settings/widgets/settings_drawer.dart';
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

  String _userName = '';
  StreamSubscription<String>? _nameSub;

  final ValueNotifier<List<AppointmentRecord>> _selectedEvents = ValueNotifier(
    [],
  );

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late AppointmentDateRange _appointmentRange;
  PhotoUploadNotifier? _uploadNotifier;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _appointmentRange = AppointmentDateRange.visibleMonth(_focusedDay);
    _initStreams();
  }

  void _initStreams() {
    final repo = ref.read(employeesRepositoryProvider);
    _nameSub = repo.loggedInUserNameStream().listen((name) {
      if (mounted) setState(() => _userName = name);
    });

    _uploadNotifier = ref.read(photoUploadNotifierProvider);
    _uploadNotifier?.latestFailure.addListener(_onUploadFailure);
  }

  @override
  void dispose() {
    _uploadNotifier?.latestFailure.removeListener(_onUploadFailure);
    _nameSub?.cancel();
    _selectedEvents.dispose();
    super.dispose();
  }

  void _onUploadFailure() {
    final failure = _uploadNotifier?.latestFailure.value;
    if (failure == null || !mounted) return;
    final appointmentId = failure.appointmentId;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        backgroundColor: scheme.errorContainer,
        content: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.photoUploadFailedSnackbar,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: context.l10n.open,
          textColor: scheme.onErrorContainer,
          onPressed: () async {
            final appointment = await ref
                .read(appointmentsRepositoryProvider)
                .getAppointmentById(appointmentId);
            if (!mounted || appointment == null) return;
            showEventDetails(context, appointment, showActions: widget.isAdmin);
          },
        ),
      ),
    );
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

  Map<DateTime, List<AppointmentRecord>> _buildDayIndex(
    List<AppointmentRecord> source,
  ) {
    final index = <DateTime, List<AppointmentRecord>>{};
    for (final app in source) {
      final start = app.startTime;
      final key = DateTime(start.year, start.month, start.day);
      (index[key] ??= <AppointmentRecord>[]).add(app);
    }
    for (final list in index.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return index;
  }

  List<AppointmentRecord> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final myAppointmentsKey = (
      employeeId: widget.employeeId,
      range: _appointmentRange,
    );
    final appointmentsAsync = widget.isAdmin
        ? ref.watch(appointmentsInRangeProvider(_appointmentRange))
        : ref.watch(myAppointmentsProvider(myAppointmentsKey));

    void onAsyncChange(
      AsyncValue<List<AppointmentRecord>>? previous,
      AsyncValue<List<AppointmentRecord>> next,
    ) {
      if (next is AsyncError && previous is! AsyncError) {
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.couldNotLoadAppointments);
      }
    }

    if (widget.isAdmin) {
      ref.listen(appointmentsInRangeProvider(_appointmentRange), onAsyncChange);
    } else {
      ref.listen(myAppointmentsProvider(myAppointmentsKey), onAsyncChange);
    }

    final employees =
        ref.watch(allUsersStreamProvider).asData?.value ?? const [];
    final colorMap = buildEmployeeColorMap(employees);

    final visibleAppointments = appointmentsAsync.when(
      data: (data) => data,
      loading: () => const <AppointmentRecord>[],
      error: (err, stack) {
        ref.read(loggerProvider).warn('appointments stream error', err, stack);
        return const <AppointmentRecord>[];
      },
    );

    _dayIndex = _buildDayIndex(visibleAppointments);

    final selectedDay = _selectedDay ?? _focusedDay;
    final selectedEvents = _getEventsForDay(selectedDay);
    _selectedEvents.value = selectedEvents;

    final isLoading = appointmentsAsync.isLoading;
    final locale = Localizations.localeOf(context).toString();
    final monthLabel = DateFormat.yMMMM(locale).format(_focusedDay);
    final jobLabel = '${selectedEvents.length} ${context.l10n.appointments}';

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        automaticallyImplyLeading: false,
        title: Text(
          context.l10n.calendar,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: scheme.onPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _goToToday,
            child: Text(
              context.l10n.today,
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.menu, color: scheme.onPrimary),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () async {
                    final picked = await MonthYearPicker.show(
                      context,
                      _focusedDay,
                    );
                    if (picked != null) _setFocusedDay(picked);
                  },
                  child: Text(
                    monthLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onPrimary.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                Text(
                  jobLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onPrimary.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: () async {
                final newEvent = await showAddEventPopup(
                  context,
                  initialDate: _selectedDay ?? _focusedDay,
                );
                if (newEvent != null) {
                  await ref
                      .read(appointmentsRepositoryProvider)
                      .addAppointment(newEvent);
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
      endDrawer: SettingsDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        userName: _userName,
      ),
      body: SafeArea(
        child: _content(
          isLoading: isLoading,
          colorMap: colorMap,
          employees: employees,
        ),
      ),
    );
  }

  Widget _content({
    required bool isLoading,
    required Map<String, Color> colorMap,
    required List<EmployeeRecord> employees,
  }) {
    final screenSize = MediaQuery.sizeOf(context);
    final isTablet = screenSize.width > 600;

    return Column(
      children: [
        AppCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: _onDaySelected,
          rowHeight: isTablet
              ? screenSize.height * 0.08
              : screenSize.height * 0.065,
          eventLoader: _getEventsForDay,
          onCalendarCreated: (_) {},
          onPageChanged: _setFocusedDay,
          employees: employees,
          employeeColorMap: colorMap,
        ),
        const SizedBox(height: AppSpacing.sp12),
        const Divider(),
        EventList(
          events: _selectedEvents,
          employees: employees,
          isLoading: isLoading,
          isAdmin: widget.isAdmin,
        ),
      ],
    );
  }
}
