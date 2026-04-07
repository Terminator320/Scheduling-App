import 'package:flutter/material.dart';
import 'package:scheduling/models/appointment_record.dart';
import 'package:table_calendar/table_calendar.dart';


class AppCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Function(DateTime, DateTime) onDaySelected;
  final List<AppointmentRecord> Function(DateTime) eventLoader;
  final Function(PageController)? onCalendarCreated;
  final Function(DateTime)? onPageChanged;
  final double? rowHeight;

  const AppCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.eventLoader,
    this.onCalendarCreated,
    this.onPageChanged,
    this.rowHeight,
  });

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      firstDay: DateTime(focusedDay.year - 10, 1, 1),
      lastDay: DateTime(focusedDay.year + 10, 12, 31),
      focusedDay: focusedDay,

      rowHeight: rowHeight ?? 48,

      selectedDayPredicate: (day) =>
          isSameDay(selectedDay, day),

      eventLoader: eventLoader,
      headerVisible: false,

      onDaySelected: onDaySelected,
      onCalendarCreated: onCalendarCreated,
      onPageChanged: onPageChanged,

      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(fontSize: 16),
      ),

      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return const SizedBox();

          return Positioned(
            bottom: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                events.length > 3 ? 3 : events.length,
                    (_) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}