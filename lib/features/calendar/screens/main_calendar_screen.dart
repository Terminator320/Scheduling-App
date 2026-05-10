import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/services/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/app_calendar_view.dart';
import 'package:scheduling/features/calendar/widgets/calendar_header.dart';
import 'package:scheduling/features/calendar/widgets/event_list.dart';
import 'package:scheduling/features/calendar/widgets/month_year_picker.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/settings/widgets/settings_drawer.dart';

class MainCalendar extends StatefulWidget {
  final bool isAdmin;
  final String employeeId;

  const MainCalendar({
    super.key,
    required this.isAdmin,
    required this.employeeId,
  });

  @override
  State<MainCalendar> createState() => _MainCalendar();
}

class _MainCalendar extends State<MainCalendar> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final service = AppointmentService();
  final userService = FirebaseEmployeesRepository(FirebaseFirestore.instance);

  StreamSubscription? _nameSub;
  StreamSubscription? _employeesSub;
  StreamSubscription? _appointmentsSub;

  PageController? _pageController;
  String _userName = '';
  List<EmployeeRecord> _allEmployees = [];
  bool _isLoading = true;

  final ValueNotifier<List<AppointmentRecord>> _selectedEvents = ValueNotifier(
    [],
  );

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<AppointmentRecord> _allAppointments = [];
  late AppointmentDateRange _appointmentRange;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _initStreams();
  }

  void _initStreams() {
    _nameSub = userService.loggedInUserNameStream().listen((name) {
      if (mounted) setState(() => _userName = name);
    });

    _employeesSub = userService.watchAllUsers().listen((data) {
      if (mounted) setState(() => _allEmployees = data);
    });

    PhotoUploadNotifier.instance.latestFailure.addListener(_onUploadFailure);
    _subscribeAppointmentsForFocusedMonth();
  }

  void _onUploadFailure() {
    final failure = PhotoUploadNotifier.instance.latestFailure.value;
    if (failure == null || !mounted) return;
    final appointmentId = failure.appointmentId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.photoUploadFailedSnackbar),
        action: SnackBarAction(
          label: context.l10n.open,
          onPressed: () async {
            final appointment = await AppointmentService().getAppointmentById(appointmentId);
            if (!mounted || appointment == null) return;
            showEventDetails(context, appointment);
          },
        ),
      ),
    );
  }

  void _subscribeAppointmentsForFocusedMonth() {
    if (mounted) setState(() => _isLoading = true);
    // Listen only to appointments near the visible month instead of the whole collection.
    _appointmentRange = AppointmentDateRange.visibleMonth(_focusedDay);
    _appointmentsSub?.cancel();
    _appointmentsSub = service.appointmentsInRange(_appointmentRange).listen((
      data,
    ) {
      if (!mounted) return;
      setState(() {
        _allAppointments = widget.isAdmin
            ? data
            : data
                  .where((a) => a.employeeIds.contains(widget.employeeId))
                  .toList();
        if (_isLoading) _isLoading = false;
      });
      _selectedEvents.value = _getEventsForDay(_selectedDay!);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    final oldRange = _appointmentRange;
    setState(() {
      _focusedDay = now;
      _selectedDay = now;
    });
    final newRange = AppointmentDateRange.visibleMonth(now);
    if (newRange.start != oldRange.start || newRange.end != oldRange.end) {
      _subscribeAppointmentsForFocusedMonth();
    }
    _selectedEvents.value = _getEventsForDay(now);
  }

  void _setFocusedDay(DateTime day) {
    final oldRange = _appointmentRange;
    setState(() => _focusedDay = day);
    final newRange = AppointmentDateRange.visibleMonth(day);
    // Resubscribe only when paging moves outside the currently loaded range.
    if (newRange.start != oldRange.start || newRange.end != oldRange.end) {
      _subscribeAppointmentsForFocusedMonth();
    }
  }

  @override
  void dispose() {
    PhotoUploadNotifier.instance.latestFailure.removeListener(_onUploadFailure);
    _nameSub?.cancel();
    _employeesSub?.cancel();
    _appointmentsSub?.cancel();
    _selectedEvents.dispose();
    super.dispose();
  }

  Map<String, Color> get _employeeColorMap =>
      buildEmployeeColorMap(_allEmployees);

  List<AppointmentRecord> _getEventsForDay(DateTime day) {
    final events = _allAppointments.where((app) {
      return isSameDay(app.startTime, day);
    }).toList();
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      final oldRange = _appointmentRange;
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });

      final newRange = AppointmentDateRange.visibleMonth(focusedDay);
      if (newRange.start != oldRange.start || newRange.end != oldRange.end) {
        _subscribeAppointmentsForFocusedMonth();
      }
      _selectedEvents.value = _getEventsForDay(selectedDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final monthLabel = _formatMonth(locale);
    final jobCount = _selectedEvents.value.length;
    final jobLabel = '$jobCount ${context.l10n.appointments}';

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(
          context.l10n.calendar,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _goToToday,
            child: Text(
              context.l10n.today,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
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
                    final picked =
                        await MonthYearPicker.show(context, _focusedDay);
                    if (picked != null) _setFocusedDay(picked);
                  },
                  child: Text(
                    monthLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                Text(
                  jobLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.82),
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
                  await service.addAppointment(newEvent);
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
      body: SafeArea(child: content()),
    );
  }

  String _formatMonth(String locale) {
    try {
      return '${_monthName()} ${_focusedDay.year}';
    } catch (_) {
      return '${_focusedDay.year}';
    }
  }

  String _monthName() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return months[_focusedDay.month - 1];
  }

  Widget content() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Column(
      children: [
        // CalendarHeader(
        //   focusedDay: _focusedDay,
        //   onLeft: () => _pageController?.previousPage(
        //     duration: const Duration(milliseconds: 300),
        //     curve: Curves.easeOut,
        //   ),
        //   onRight: () => _pageController?.nextPage(
        //     duration: const Duration(milliseconds: 300),
        //     curve: Curves.easeOut,
        //   ),
        //   onToday: () {
        //     final now = DateTime.now();
        //     setState(() {
        //       _focusedDay = now;
        //       _selectedDay = now;
        //       _selectedEvents.value = _getEventsForDay(now);
        //     });
        //     _subscribeAppointmentsForFocusedMonth();
        //   },
        //   onTapMonth: () async {
        //     final picked = await MonthYearPicker.show(context, _focusedDay);
        //     if (picked != null) _setFocusedDay(picked);
        //   },
        // ),

        AppCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: _onDaySelected,
          rowHeight: isTablet ? screenHeight * 0.08 : screenHeight * 0.065,
          eventLoader: _getEventsForDay,
          onCalendarCreated: (controller) => _pageController = controller,
          onPageChanged: _setFocusedDay,
          employees: _allEmployees,
          employeeColorMap: _employeeColorMap,
        ),

        const SizedBox(height: AppSpacing.sp12),
        const Divider(),

        EventList(
          events: _selectedEvents,
          employees: _allEmployees,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}
