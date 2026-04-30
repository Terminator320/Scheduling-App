import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/app_calendar_view.dart';
import 'package:scheduling/features/calendar/widgets/calendar_header.dart';
import 'package:scheduling/features/calendar/widgets/event_list.dart';
import 'package:scheduling/features/calendar/widgets/month_year_picker.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
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
  final userService = UserService();

  StreamSubscription? _nameSub;
  StreamSubscription? _employeesSub;
  StreamSubscription? _appointmentsSub;

  PageController? _pageController;
  String _userName = '';
  List<EmployeeRecord> _allEmployees = [];

  final ValueNotifier<List<AppointmentRecord>> _selectedEvents = ValueNotifier(
    [],
  );

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<AppointmentRecord> _allAppointments = [];

  @override
  void initState() {
    super.initState();

    _selectedDay = _focusedDay;

    _nameSub = userService.loggedInUserNameStream().listen((name) {
      if (mounted) setState(() => _userName = name);
    });

    _employeesSub = userService.allUsersStream().listen((data) {
      if (mounted) {
        setState(() {
          _allEmployees = data;
        });
      }
    });

    _appointmentsSub = service.getAllAppointments().listen((data) {
      if (mounted) {
        setState(() {
          // Employees only see appointments assigned to them
          if (widget.isAdmin) {
            _allAppointments = data;
          } else {
            _allAppointments = data
                .where((a) => a.employeeIds.contains(widget.employeeId))
                .toList();
          }
        });

        _selectedEvents.value = _getEventsForDay(_selectedDay!);
      }
    });
  }

  @override
  void dispose() {
    _nameSub?.cancel();
    _employeesSub?.cancel();
    _appointmentsSub?.cancel();
    _selectedEvents.dispose();
    super.dispose();
  }

  Map<String, Color> get _employeeColorMap => buildEmployeeColorMap(_allEmployees);

  List<AppointmentRecord> _getEventsForDay(DateTime day) {
    final events = _allAppointments.where((app) {
      return isSameDay(app.startTime, day);
    }).toList();
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });

      _selectedEvents.value = _getEventsForDay(selectedDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: () async {
                final newEvent = await showAddEventPopup(context);

                if (newEvent != null) {
                  await service.addAppointment(newEvent);
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
      endDrawer: SettingsDrawer(isAdmin: widget.isAdmin, employeeId: widget.employeeId,),
      body: SafeArea(child: content()),
    );
  }

  Widget content() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hello, $_userName',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.menu),
                visualDensity: VisualDensity.compact,
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
            ],
          ),
        ),
        CalendarHeader(
          focusedDay: _focusedDay,
          onLeft: () => _pageController?.previousPage(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
          onRight: () => _pageController?.nextPage(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
          onToday: () {
            final now = DateTime.now();
            setState(() {
              _focusedDay = now;
              _selectedDay = now;
              _selectedEvents.value = _getEventsForDay(now);
            });
          },
          onTapMonth: () async {
            final picked = await MonthYearPicker.show(context, _focusedDay);

            if (picked != null) {
              setState(() {
                _focusedDay = picked;
              });
            }
          },
        ),

        AppCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: _onDaySelected,
          rowHeight: isTablet ? screenHeight * 0.08 : screenHeight * 0.065,
          eventLoader: _getEventsForDay,
          onCalendarCreated: (controller) => _pageController = controller,
          onPageChanged: (day) => setState(() => _focusedDay = day),
          employees: _allEmployees,
          employeeColorMap: _employeeColorMap,
        ),

        SizedBox(height: 10),

        Divider(),

        EventList(
          events: _selectedEvents,
          employees: _allEmployees,
        ),
      ],
    );
  }
}
