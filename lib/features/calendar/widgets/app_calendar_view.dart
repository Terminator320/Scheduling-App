import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';


class AppCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Function(DateTime, DateTime) onDaySelected;
  final List<AppointmentRecord> Function(DateTime) eventLoader;
  final Function(PageController)? onCalendarCreated;
  final Function(DateTime)? onPageChanged;
  final double? rowHeight;

  final List<EmployeeRecord> employees;
  final Map<String, Color> employeeColorMap;

  const AppCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.eventLoader,
    required this.employees,
    required this.employeeColorMap,
    this.onCalendarCreated,
    this.onPageChanged,
    this.rowHeight,
  });


  Widget _dayCell(
    BuildContext context,
    DateTime day, {
    required BoxDecoration decoration,
    TextStyle? textStyle,
    required double rowH,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        const markerSpace = 12.0;
        final availableHeight = (maxH - markerSpace).clamp(0.0, double.infinity);
        final circleSize = availableHeight < 20
            ? availableHeight
            : availableHeight.clamp(20.0, 36.0);

        return Padding(
          padding: const EdgeInsets.only(bottom: markerSpace),
          child: Center(
            child: Container(
              width: circleSize,
              height: circleSize,
              decoration: decoration,
              alignment: Alignment.center,
              child: Text('${day.day}', style: textStyle),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRowH = rowHeight ?? 56.0;
    return TableCalendar(
      firstDay: DateTime(focusedDay.year - 10, 1, 1),
      lastDay: DateTime(focusedDay.year + 10, 12, 31),
      focusedDay: focusedDay,

      rowHeight: rowHeight ?? 56,
      daysOfWeekHeight: 36,

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
        todayBuilder: (context, day, focusedDay) {
          return _dayCell(
            context,
            day,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface,
                width: 1.5,
              ),
            ),
            textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            rowH: effectiveRowH,
          );
        },
        selectedBuilder: (context, day, focusedDay) {
          return _dayCell(
            context,
            day,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
            rowH: effectiveRowH,
          );
        },
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return const SizedBox();

          final appointments = events.cast<AppointmentRecord>();

          return Positioned(
            bottom: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: appointments.take(3).map((appt) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colorFromMap(appt, employeeColorMap) ?? Colors.grey,
                    shape: BoxShape.circle,
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
