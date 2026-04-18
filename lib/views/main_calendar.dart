import 'package:flutter/material.dart';
import 'package:scheduling/models/appointment_record.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/employee_record.dart';
import '../services/appointment_service.dart';

import '../services/user_service.dart';
import '../utils/calendar_utils/sheet_helpers.dart';

import '../widgets/calendar_widgets/month_year_picker.dart';
import '../widgets/calendar_widgets/app_calendar_view.dart';
import '../widgets/calendar_widgets/calendar_header.dart';
import '../widgets/calendar_widgets/event_list.dart';
import '../widgets/settings_drawer.dart';

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

    userService.loggedInUserNameStream().listen((name) {
      if (mounted) setState(() => _userName = name);
    });

    userService.allUsersStream().listen((data) {
      setState(() {
        _allEmployees = data;
      });
    });

    service.getAllAppointments().listen((data) {
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
    });
  }

  @override
  void dispose() {
    _selectedEvents.dispose();
    super.dispose();
  }

  List<AppointmentRecord> _getEventsForDay(DateTime day) {
    return _allAppointments.where((app) {
      return isSameDay(app.startTime, day);
    }).toList();
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
      endDrawer: SettingsDrawer(isAdmin: widget.isAdmin),
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
