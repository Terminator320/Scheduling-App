import 'package:flutter/material.dart';
import 'package:scheduling/models/appointment_record.dart';
import 'package:table_calendar/table_calendar.dart';

import '../Widgets/month_year_picker.dart';

import '../services/appointment_service.dart';

import '../utils/date_utils_helper.dart';
import '../utils/sheet_helpers.dart';
import '../widgets/app_calendar_view.dart';
import '../widgets/calendar_header.dart';
import '../widgets/event_list.dart';

class MainCalendar extends StatefulWidget {
  const MainCalendar({super.key});

  @override
  State<MainCalendar> createState() => _MainCalendar();
}

class _MainCalendar extends State<MainCalendar> {
  final service = AppointmentService();
  PageController? _pageController;

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

    service.getAllAppointments().listen((data) {
      setState(() {
        _allAppointments = data;
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final newEvent = await showAddEventPopup(context);

          if (newEvent != null) {
            await service.addAppointment(newEvent);
          }
        },
        child: Icon(Icons.add),
      ),
      body: SafeArea(child: content()),
    );
  }

  Widget content() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Column(
      children: [
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
          rowHeight: isTablet ? screenHeight * 0.08 : screenHeight * 0.07,
          eventLoader: _getEventsForDay,
          onCalendarCreated: (controller) => _pageController = controller,
          onPageChanged: (day) => setState(() => _focusedDay = day),
        ),

        SizedBox(height: 10),

        Divider(),

        EventList(
          events: _selectedEvents,
        ),
      ],
    );
  }
}
