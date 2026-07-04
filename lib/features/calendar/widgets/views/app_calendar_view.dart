import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/appointment_colors.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:table_calendar/table_calendar.dart';

class AppCalendar extends StatelessWidget {
  const AppCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.eventLoader,
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

  final Map<String, Color> employeeColorMap;

  Widget _dayCell(
    DateTime day, {
    required BoxDecoration decoration,
    TextStyle? textStyle,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
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

      // Accessibility note: table_calendar wraps every day cell — default
      // cells AND the todayBuilder/selectedBuilder output below — in its own
      // `Semantics(label: '<weekday>, <full date>', excludeSemantics: true)`,
      // and the cell's GestureDetector contributes the tap action. That
      // built-in wrapper gives all cells a localized full-date label, but it
      // also swallows any Semantics added inside these builders, so the
      // selected/today state can't be exposed per cell from here. The
      // appointment count IS announced: markerBuilder output sits beside the
      // cell's semantics node in the cell Stack, so its label survives and
      // merges into the cell's announcement, e.g.
      // "Saturday, May 16, 2026 \n 2 appointments" (see markerBuilder below).
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
          final fallback = Theme.of(context).colorScheme.outline;

          // The dots are colour-only, so exclude them from semantics and
          // announce the day's appointment count instead; the label merges
          // into the cell's full-date node (see the note on calendarBuilders).
          // `events` is already loaded for this cell, so the label stays O(1)
          // per cell.
          return Positioned(
            bottom: 2,
            child: Semantics(
              label: context.l10n.calendar_appointmentCount(events.length),
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final appt in appointments.take(3))
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colorFromMap(appt, employeeColorMap) ?? fallback,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
