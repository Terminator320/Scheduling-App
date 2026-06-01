import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:table_calendar/table_calendar.dart';

class AppCalendar extends StatelessWidget {
  const AppCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.eventLoader,
    required this.employees,
    required this.employeeColorMap,
    super.key,
    this.onCalendarCreated,
    this.onPageChanged,
    this.rowHeight,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final List<AppointmentRecord> Function(DateTime) eventLoader;
  final void Function(PageController)? onCalendarCreated;
  final void Function(DateTime)? onPageChanged;
  final double? rowHeight;

  final List<EmployeeRecord> employees;
  final Map<String, Color> employeeColorMap;

  Widget _dayCell(
    DateTime day, {
    required BoxDecoration decoration,
    TextStyle? textStyle,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        // NOTE: reserved space for the event-marker dots; precise layout math,
        // not a themeable spacing token.
        const markerSpace = 12.0;
        final availableHeight = (maxH - markerSpace).clamp(
          0.0,
          double.infinity,
        );
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
    final localeCode = AppLanguageScope.of(context).value == 'fr'
        ? 'fr_CA'
        : 'en_CA';
    return TableCalendar(
      locale: localeCode,
      firstDay: DateTime(focusedDay.year - 10),
      lastDay: DateTime(focusedDay.year + 10, 12, 31),
      focusedDay: focusedDay,

      rowHeight: rowHeight ?? 56,
      daysOfWeekHeight: 36,

      selectedDayPredicate: (day) => isSameDay(selectedDay, day),

      eventLoader: eventLoader,
      headerVisible: false,

      onDaySelected: onDaySelected,
      onCalendarCreated: onCalendarCreated,
      onPageChanged: onPageChanged,

      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle:
            Theme.of(context).textTheme.titleMedium ?? const TextStyle(),
      ),

      calendarBuilders: CalendarBuilders(
        todayBuilder: (context, day, focusedDay) {
          final scheme = Theme.of(context).colorScheme;
          return _dayCell(
            day,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary,
            ),
            textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          );
        },
        selectedBuilder: (context, day, focusedDay) {
          final scheme = Theme.of(context).colorScheme;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1),
            duration: AppDuration.fast,
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: _dayCell(
              day,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return const SizedBox();

          final appointments = events.cast<AppointmentRecord>();

          return Positioned(
            bottom: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final appt in appointments.take(3))
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color:
                          colorFromMap(appt, employeeColorMap) ?? Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
