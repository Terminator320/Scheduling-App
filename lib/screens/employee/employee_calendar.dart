import 'package:flutter/material.dart';

import '../../widgets/employee_drawers.dart';
import '../../models/appointment_record.dart';
import '../../utils/colors.dart';

class EmployeeCalendarPage extends StatefulWidget {
  EmployeeCalendarPage({
    super.key,
    this.employeeName = 'Employee name',
    List<AppointmentRecord>? appointments,
  }) : appointments = appointments ?? kAppointments;

  final String employeeName;
  final List<AppointmentRecord> appointments;

  @override
  State<EmployeeCalendarPage> createState() => _EmployeeCalendarPageState();
}

class _EmployeeCalendarPageState extends State<EmployeeCalendarPage> {
  DateTime displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();

  static const Color kEmployeeEventColor = Color(0xFFE7DDF9);

  String monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<DateTime> buildCalendarDays(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final startOffset = firstDayOfMonth.weekday % 7;
    final firstVisibleDay = firstDayOfMonth.subtract(Duration(days: startOffset));

    return List.generate(42, (index) => firstVisibleDay.add(Duration(days: index)));
  }

  DateTime? _parseDisplayDate(String value) {
    final slashParts = value.split('/');
    if (slashParts.length == 3) {
      final day = int.tryParse(slashParts[0].trim());
      final month = int.tryParse(slashParts[1].trim());
      final year = int.tryParse(slashParts[2].trim());
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  Map<String, List<Map<String, dynamic>>> get events {
    final Map<String, List<Map<String, dynamic>>> mapped = {};

    final employeeAppointments = widget.appointments.where((appointment) {
      return appointment.assignedEmployee.trim().toLowerCase() ==
          widget.employeeName.trim().toLowerCase();
    });

    for (final appointment in employeeAppointments) {
      final parsedDate = _parseDisplayDate(appointment.date);
      if (parsedDate == null) continue;

      final key = dateKey(parsedDate);
      mapped.putIfAbsent(key, () => []);
      mapped[key]!.add({
        'title': appointment.title,
        'date': appointment.date,
        'time': '${appointment.startTime}-${appointment.endTime}',
        'client': '${appointment.clientName} (${appointment.clientPhone})',
        'address': appointment.address,
        'jobType': appointment.jobType,
        'notes': appointment.notes,
        'subtitle': appointment.notes,
        'materials': appointment.materialsNeeded,
        'pictures': appointment.pictures,
        'color': kEmployeeEventColor,
      });
    }

    return mapped;
  }

  @override
  Widget build(BuildContext context) {
    final calendarDays = buildCalendarDays(displayedMonth);
    final selectedEvents = events[dateKey(selectedDate)] ?? [];
    final today = DateTime.now();

    return Scaffold(
      endDrawer: EmployeeMenu(
        employeeName: widget.employeeName,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    widget.employeeName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu, size: 28),
                      onPressed: () {
                        Scaffold.of(context).openEndDrawer();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CalendarArrowButton(
                    icon: Icons.chevron_left,
                    onTap: () {
                      setState(() {
                        displayedMonth = DateTime(
                          displayedMonth.year,
                          displayedMonth.month - 1,
                        );
                        if (selectedDate.month != displayedMonth.month ||
                            selectedDate.year != displayedMonth.year) {
                          selectedDate = DateTime(
                            displayedMonth.year,
                            displayedMonth.month,
                            1,
                          );
                        }
                      });
                    },
                  ),
                  Column(
                    children: [
                      Text(
                        monthName(displayedMonth.month),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${displayedMonth.year}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  _CalendarArrowButton(
                    icon: Icons.chevron_right,
                    onTap: () {
                      setState(() {
                        displayedMonth = DateTime(
                          displayedMonth.year,
                          displayedMonth.month + 1,
                        );
                        if (selectedDate.month != displayedMonth.month ||
                            selectedDate.year != displayedMonth.year) {
                          selectedDate = DateTime(
                            displayedMonth.year,
                            displayedMonth.month,
                            1,
                          );
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: const [
                  Expanded(child: Center(child: Text('Sun', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Mon', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Tue', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Wed', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Thu', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Fri', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Sat', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: calendarDays.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final day = calendarDays[index];
                  final isCurrentMonth = day.month == displayedMonth.month;
                  final isSelected = isSameDate(day, selectedDate);
                  final isToday = isSameDate(day, today);
                  final hasEvents = (events[dateKey(day)] ?? []).isNotEmpty;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedDate = day;
                      });
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? kPurple : Colors.transparent,
                            border: isToday && !isSelected
                                ? Border.all(color: kPurple, width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? Colors.white
                                  : isCurrentMonth
                                      ? Colors.black
                                      : Colors.black38,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (hasEvents)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: kPurple,
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const SizedBox(height: 5),
                      ],
                    ),
                  );
                },
              ),
              const Divider(),
              const SizedBox(height: 10),
              Expanded(
                child: selectedEvents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.event_note_rounded,
                              size: 42,
                              color: Colors.black38,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No events for ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: selectedEvents.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final event = selectedEvents[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kEmployeeEventColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        event['time'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        showEmployeeEventPopup(
                                          context,
                                          event: event,
                                        );
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.more_horiz,
                                          color: Colors.black54,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  event['title'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if ((event['subtitle'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    event['subtitle'],
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarArrowButton extends StatelessWidget {
  const _CalendarArrowButton({
    required this.icon,
    required this.onTap,
    this.isDark = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFD7D7D7),
          ),
          borderRadius: BorderRadius.circular(14),
          color: isDark ? Colors.black : Colors.white,
        ),
        child: Icon(
          icon,
          size: 24,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      ),
    );
  }
}

Future<void> showEmployeeEventPopup(
  BuildContext context, {
  required Map<String, dynamic> event,
}) async {
  final timeRange = (event['time'] ?? '').toString().split('-');
  final eventNameController = TextEditingController(
    text: (event['title'] ?? '').toString(),
  );
  final dateController = TextEditingController(
    text: (event['date'] ?? '').toString(),
  );
  final startTimeController = TextEditingController(
    text: timeRange.isNotEmpty ? timeRange.first.trim() : '',
  );
  final endTimeController = TextEditingController(
    text: timeRange.length > 1 ? timeRange.last.trim() : '',
  );
  final clientController = TextEditingController(
    text: (event['client'] ?? '').toString(),
  );
  final addressController = TextEditingController(
    text: (event['address'] ?? '').toString(),
  );
  final jobTypeController = TextEditingController(
    text: (event['jobType'] ?? '').toString(),
  );
  final noteController = TextEditingController(
    text: (event['notes'] ?? '').toString(),
  );
  final materialsController = TextEditingController(
    text: (event['materials'] ?? '').toString(),
  );
  final picturesController = TextEditingController(
    text: (event['pictures'] ?? '').toString(),
  );

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 44,
                          child: Divider(
                            thickness: 4,
                            color: const Color(0xFFD0D0D0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'Event',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _popupTextField(
                        controller: eventNameController,
                        hintText: 'Event name',
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      _popupTextField(
                        controller: dateController,
                        hintText: 'Date',
                        suffixIcon: Icons.calendar_today_outlined,
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _popupTextField(
                              controller: startTimeController,
                              hintText: 'Start Time',
                              suffixIcon: Icons.access_time_outlined,
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _popupTextField(
                              controller: endTimeController,
                              hintText: 'End Time',
                              suffixIcon: Icons.access_time_outlined,
                              readOnly: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _popupTextField(
                        controller: clientController,
                        hintText: 'Client name (phone number)',
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      _popupTextField(
                        controller: addressController,
                        hintText: 'Address',
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      _popupTextField(
                        controller: jobTypeController,
                        hintText: 'Type of job',
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      _popupTextField(
                        controller: noteController,
                        hintText: 'Notes',
                        suffixIcon: Icons.note_alt_outlined,
                        maxLines: 3,
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      _popupTextField(
                        controller: materialsController,
                        hintText: 'Materials needed',
                        suffixIcon: Icons.build_outlined,
                        maxLines: 3,
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      _popupTextField(
                        controller: picturesController,
                        hintText: 'Pictures',
                        suffixIcon: Icons.image_outlined,
                        maxLines: 3,
                        readOnly: true,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPurple,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Event Done',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _popupTextField({
  required TextEditingController controller,
  required String hintText,
  IconData? suffixIcon,
  int maxLines = 1,
  bool readOnly = false,
}) {
  return TextField(
    controller: controller,
    readOnly: readOnly,
    maxLines: maxLines,
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF7A7A7A),
        fontSize: 15,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 16,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kPurple),
      ),
      suffixIcon: suffixIcon == null
          ? null
          : Icon(suffixIcon, color: const Color(0xFF7A7A7A)),
    ),
  );
}


class EmployeeCalendarDarkPage extends StatefulWidget {
  EmployeeCalendarDarkPage({
    super.key,
    this.employeeName = 'Employee name',
    List<AppointmentRecord>? appointments,
  }) : appointments = appointments ?? kAppointments;

  final String employeeName;
  final List<AppointmentRecord> appointments;

  @override
  State<EmployeeCalendarDarkPage> createState() =>
      _EmployeeCalendarDarkPageState();
}

class _EmployeeCalendarDarkPageState extends State<EmployeeCalendarDarkPage> {
  late DateTime displayedMonth;
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    displayedMonth = DateTime(now.year, now.month);
    selectedDate = DateTime(now.year, now.month, now.day);
  }

  List<AppointmentRecord> get employeeAppointments {
    return widget.appointments.where((a) {
      final assigned = a.assignedEmployee.trim().toLowerCase();
      final current = widget.employeeName.trim().toLowerCase();
      return assigned == current;
    }).toList();
  }

  Map<String, List<AppointmentRecord>> get eventsByDate {
    final map = <String, List<AppointmentRecord>>{};
    for (final appointment in employeeAppointments) {
      final key = _normalizeDateString(appointment.date);
      map.putIfAbsent(key, () => []);
      map[key]!.add(appointment);
    }
    return map;
  }

  String _normalizeDateString(String input) {
    try {
      final parsed = DateTime.parse(input);
      return _dateKey(parsed);
    } catch (_) {
      return input.trim();
    }
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<DateTime> _buildCalendarDays(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final weekdayOffset = firstDayOfMonth.weekday % 7;
    final firstVisibleDay =
    firstDayOfMonth.subtract(Duration(days: weekdayOffset));

    return List.generate(
      42,
          (index) => firstVisibleDay.add(Duration(days: index)),
    );
  }

  String _monthName(int month) {
    const names = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _showEventPopup(AppointmentRecord event) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Event',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                _buildField(event.title, icon: null),
                const SizedBox(height: 12),
                _buildField(event.date, icon: Icons.calendar_today_outlined),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        event.startTime,
                        icon: Icons.access_time_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(
                        event.endTime,
                        icon: Icons.access_time_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildField(
                  '${event.clientName} (${event.clientPhone})',
                  icon: null,
                ),
                const SizedBox(height: 12),
                _buildField(event.address, icon: null),
                const SizedBox(height: 12),
                _buildField(event.jobType, icon: null),
                const SizedBox(height: 12),
                _buildLargeField(
                  event.notes.isEmpty ? 'Notes' : event.notes,
                  icon: Icons.description_outlined,
                ),
                const SizedBox(height: 12),
                _buildLargeField(
                  event.materialsNeeded.isEmpty
                      ? 'Materials needed'
                      : event.materialsNeeded,
                  icon: Icons.build_outlined,
                ),
                const SizedBox(height: 12),
                _buildLargeField(
                  event.pictures.isEmpty ? 'Pictures' : event.pictures,
                  icon: Icons.image_outlined,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Event Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(String text, {IconData? icon}) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (icon != null) Icon(icon, color: Colors.white70, size: 20),
        ],
      ),
    );
  }

  Widget _buildLargeField(String text, {IconData? icon}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
              ),
            ),
          ),
          if (icon != null) Icon(icon, color: Colors.white70, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calendarDays = _buildCalendarDays(displayedMonth);
    final selectedEvents = eventsByDate[_dateKey(selectedDate)] ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: EmployeeMenuDark(
        employeeName: widget.employeeName,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    widget.employeeName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(
                        Icons.menu,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        Scaffold.of(context).openEndDrawer();
                      },
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 18),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CalendarArrowButton(
                    icon: Icons.chevron_left,
                    isDark: true,
                    onTap: () {
                      setState(() {
                        displayedMonth = DateTime(
                          displayedMonth.year,
                          displayedMonth.month - 1,
                        );
                      });
                    },
                  ),
                  Column(
                    children: [
                      Text(
                        _monthName(displayedMonth.month),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        displayedMonth.year.toString(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  _CalendarArrowButton(
                    icon: Icons.chevron_right,
                    isDark: true,
                    onTap: () {
                      setState(() {
                        displayedMonth = DateTime(
                          displayedMonth.year,
                          displayedMonth.month + 1,
                        );
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Center(child: Text('Sun', style: WeekdayStyle()))),
                  Expanded(child: Center(child: Text('Mon', style: WeekdayStyle()))),
                  Expanded(child: Center(child: Text('Tue', style: WeekdayStyle()))),
                  Expanded(child: Center(child: Text('Wed', style: WeekdayStyle()))),
                  Expanded(child: Center(child: Text('Thu', style: WeekdayStyle()))),
                  Expanded(child: Center(child: Text('Fri', style: WeekdayStyle()))),
                  Expanded(child: Center(child: Text('Sat', style: WeekdayStyle()))),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: calendarDays.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final day = calendarDays[index];
                  final isCurrentMonth = day.month == displayedMonth.month;
                  final isSelected = _isSameDay(day, selectedDate);
                  final key = _dateKey(day);
                  final hasEvents = (eventsByDate[key] ?? []).isNotEmpty;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedDate = day;
                      });
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: isSelected
                              ? BoxDecoration(
                            color: kPurple,
                            shape: BoxShape.circle,
                          )
                              : null,
                          child: Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: isCurrentMonth
                                    ? Colors.white
                                    : Colors.white38,
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (hasEvents)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: kPurple,
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const SizedBox(height: 5),
                      ],
                    ),
                  );
                },
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 24),
              Expanded(
                child: selectedEvents.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 40,
                        color: Colors.white38,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No events for ${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
                    : ListView.separated(
                  itemCount: selectedEvents.length,
                  separatorBuilder: (_, _) =>
                  const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];

                    return GestureDetector(
                      onTap: () => _showEventPopup(event),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kPurple,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${event.startTime}-${event.endTime}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              event.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event.notes.isEmpty ? event.jobType : event.notes,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeekdayStyle extends TextStyle {
  const WeekdayStyle()
      : super(
    color: Colors.white70,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );
}

