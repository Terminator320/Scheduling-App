
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/appointment_record.dart';
import '../../models/client_record.dart';
import '../../utils/app_text.dart';
import '../../utils/colors.dart';
import '../../widgets/employee_drawers.dart';
import '../admin/clients_screens.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

const String _calendarHiddenAppointmentsCollection = 'calendarHiddenAppointments';

Future<void> _markAppointmentDoneForCalendar(AppointmentRecord appointment) async {
  await FirebaseFirestore.instance
      .collection(_calendarHiddenAppointmentsCollection)
      .doc(appointment.id)
      .set({
    'appointmentId': appointment.id,
    'hiddenAt': FieldValue.serverTimestamp(),
  });
}

DateTime? _appointmentStartDateTime(AppointmentRecord appointment) {
  try {
    final trimmedDate = appointment.date.trim();

    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmedDate)) {
      final dateParts = trimmedDate.split('-');
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      final time = _parseTimeOfDay(appointment.startTime);
      if (time == null) return null;

      return DateTime(year, month, day, time.hour, time.minute);
    }

    final slashParts = trimmedDate.split('/');
    if (slashParts.length == 3) {
      final day = int.parse(slashParts[0].trim());
      final month = int.parse(slashParts[1].trim());
      final year = int.parse(slashParts[2].trim());

      final time = _parseTimeOfDay(appointment.startTime);
      if (time == null) return null;

      return DateTime(year, month, day, time.hour, time.minute);
    }

    return null;
  } catch (_) {
    return null;
  }
}

TimeOfDay? _parseTimeOfDay(String value) {
  final raw = value.trim().toLowerCase();
  if (raw.isEmpty) return null;

  final regex = RegExp(r'^(\d{1,2}):(\d{2})(?:\s*([ap]m))?$');
  final match = regex.firstMatch(raw);
  if (match == null) return null;

  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final meridiem = match.group(3);

  if (meridiem != null) {
    if (hour == 12) {
      hour = meridiem == 'am' ? 0 : 12;
    } else if (meridiem == 'pm') {
      hour += 12;
    }
  }

  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

bool _hasAppointmentStarted(AppointmentRecord appointment) {
  final start = _appointmentStartDateTime(appointment);
  if (start == null) return false;
  return !DateTime.now().isBefore(start);
}

List<String> _splitStoredValues(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return [];

  return trimmed
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

List<String> _uniqueNormalizedValues(Iterable<String> values) {
  final seen = <String>{};
  final unique = <String>[];

  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;

    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      unique.add(trimmed);
    }
  }

  return unique;
}

List<String> _stringListFromDynamic(dynamic value) {
  if (value == null) return [];

  if (value is String) {
    return _splitStoredValues(value);
  }

  if (value is Iterable) {
    return value.expand((item) => _stringListFromDynamic(item)).toList();
  }

  if (value is Map) {
    final values = <String>[];
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key.contains('name') || key.contains('employee')) {
        values.addAll(_stringListFromDynamic(entry.value));
      }
      if (key == 'id' || key.endsWith('id')) {
        values.addAll(_stringListFromDynamic(entry.value));
      }
    }
    return values;
  }

  return [value.toString().trim()];
}

class _AttachedEmployeesInfo {
  final List<String> names;
  final List<String> ids;

  const _AttachedEmployeesInfo({
    required this.names,
    required this.ids,
  });

  int get count => names.length > ids.length ? names.length : ids.length;

  String displayText(BuildContext context) {
    final attachedCount = count;
    if (attachedCount <= 0) return '';

    if (attachedCount == 1) {
      if (names.isNotEmpty) return names.first;
      return tr(context, '1 employee attached');
    }

    if (names.isNotEmpty) {
      return names.join(', ');
    }

    return attachedCount == 1
        ? tr(context, '1 employee attached')
        : '${tr(context, 'Employees attached')} ($attachedCount)';
  }
}

_AttachedEmployeesInfo _attachedEmployeesInfoFromAppointment(AppointmentRecord appointment) {
  return _AttachedEmployeesInfo(
    names: _uniqueNormalizedValues(_splitStoredValues(appointment.employeeName)),
    ids: _uniqueNormalizedValues(_splitStoredValues(appointment.employeeId)),
  );
}

_AttachedEmployeesInfo _attachedEmployeesInfoFromMap(Map<String, dynamic> data) {
  final names = <String>[];
  final ids = <String>[];

  void addNames(dynamic value) => names.addAll(_stringListFromDynamic(value));
  void addIds(dynamic value) => ids.addAll(_stringListFromDynamic(value));

  addNames(data['employeeName']);
  addNames(data['employeeNames']);
  addNames(data['assignedEmployeeNames']);
  addNames(data['selectedEmployeeNames']);

  addIds(data['employeeId']);
  addIds(data['employeeIds']);
  addIds(data['assignedEmployeeIds']);
  addIds(data['selectedEmployeeIds']);

  for (final key in ['selectedEmployees', 'employees', 'assignedEmployees']) {
    final raw = data[key];
    if (raw is Iterable) {
      for (final item in raw) {
        if (item is Map) {
          addNames(item['name']);
          addNames(item['fullName']);
          addNames(item['displayName']);
          addIds(item['id']);
          addIds(item['employeeId']);
        } else {
          addNames(item);
        }
      }
    }
  }

  return _AttachedEmployeesInfo(
    names: _uniqueNormalizedValues(names),
    ids: _uniqueNormalizedValues(ids),
  );
}

Future<_AttachedEmployeesInfo> _loadAttachedEmployeesInfo(AppointmentRecord appointment) async {
  final fallback = _attachedEmployeesInfoFromAppointment(appointment);
  final appointmentId = appointment.id.trim();
  if (appointmentId.isEmpty) return fallback;

  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .doc(appointmentId)
        .get();

    if (!snapshot.exists || snapshot.data() == null) {
      return fallback;
    }

    final fromDoc = _attachedEmployeesInfoFromMap(snapshot.data()!);
    if (fromDoc.count > fallback.count ||
        (fromDoc.count == fallback.count && fromDoc.names.length > fallback.names.length)) {
      return fromDoc;
    }
  } catch (_) {}

  return fallback;
}

String _employeesAttachedText(AppointmentRecord appointment, BuildContext context) {
  return _attachedEmployeesInfoFromAppointment(appointment).displayText(context);
}

bool _appointmentMatchesEmployee(
    AppointmentRecord appointment, {
      required String employeeId,
      required String employeeName,
    }) {
  final normalizedId = employeeId.trim().toLowerCase();
  final normalizedName = employeeName.trim().toLowerCase();

  final appointmentIds = _uniqueNormalizedValues(
    _splitStoredValues(appointment.employeeId),
  ).map((value) => value.toLowerCase()).toList();

  final appointmentNames = _uniqueNormalizedValues(
    _splitStoredValues(appointment.employeeName),
  ).map((value) => value.toLowerCase()).toList();

  if (normalizedId.isNotEmpty && appointmentIds.contains(normalizedId)) {
    return true;
  }

  if (normalizedName.isNotEmpty && appointmentNames.contains(normalizedName)) {
    return true;
  }

  return false;
}

Stream<List<AppointmentRecord>> _employeeAppointmentsStream({
  required String employeeId,
  required String employeeName,
}) {
  return FirebaseFirestore.instance
      .collection('appointments')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
        .map((doc) => AppointmentRecord.fromDoc(doc))
        .where(
          (appointment) => _appointmentMatchesEmployee(
        appointment,
        employeeId: employeeId,
        employeeName: employeeName,
      ),
    )
        .toList(),
  );
}


Future<ClientRecord?> _findClientForAppointment(AppointmentRecord appointment) async {
  final clients = FirebaseFirestore.instance.collection('clients');

  final clientId = appointment.clientId.trim();
  if (clientId.isNotEmpty) {
    final byId = await clients.doc(clientId).get();
    if (byId.exists) {
      return ClientRecord.fromDoc(byId);
    }
  }

  final clientName = appointment.clientName.trim();
  if (clientName.isNotEmpty) {
    final businessMatch = await clients
        .where('businessName', isEqualTo: clientName)
        .limit(1)
        .get();
    if (businessMatch.docs.isNotEmpty) {
      return ClientRecord.fromDoc(businessMatch.docs.first);
    }

    final nameMatch = await clients
        .where('name', isEqualTo: clientName)
        .limit(1)
        .get();
    if (nameMatch.docs.isNotEmpty) {
      return ClientRecord.fromDoc(nameMatch.docs.first);
    }
  }

  final clientPhone = appointment.clientPhone.trim();
  if (clientPhone.isNotEmpty) {
    final phoneMatch = await clients
        .where('phone', isEqualTo: clientPhone)
        .limit(1)
        .get();
    if (phoneMatch.docs.isNotEmpty) {
      return ClientRecord.fromDoc(phoneMatch.docs.first);
    }
  }

  return null;
}

Future<void> _openClientDetailsForAppointment(
    BuildContext context,
    AppointmentRecord appointment, {
      required bool isDark,
    }) async {
  final client = await _findClientForAppointment(appointment);

  if (!context.mounted) return;

  if (client == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, 'Client not found')),
      ),
    );
    return;
  }

  if (isDark) {
    await showClientDetailsDarkPopup(context, client: client);
  } else {
    await showClientDetailsPopup(context, client: client);
  }
}

class EmployeeCalendarPage extends StatefulWidget {
  const EmployeeCalendarPage({
    super.key,
    required this.employeeId,
    this.employeeName = 'Employee name',
  });

  final String employeeId;
  final String employeeName;

  @override
  State<EmployeeCalendarPage> createState() => _EmployeeCalendarPageState();
}

class _EmployeeCalendarPageState extends State<EmployeeCalendarPage> {
  DateTime displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();

  static const Color kEmployeeEventColor = Color(0xFFE7DDF9);

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

    return List.generate(
      42,
          (index) => firstVisibleDay.add(Duration(days: index)),
    );
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

  Map<String, List<AppointmentRecord>> mapEvents(
      List<AppointmentRecord> appointments,
      ) {
    final mapped = <String, List<AppointmentRecord>>{};

    for (final appointment in appointments) {
      final parsedDate = _parseDisplayDate(appointment.date);
      if (parsedDate == null) continue;

      final key = dateKey(parsedDate);
      mapped.putIfAbsent(key, () => []);
      mapped[key]!.add(appointment);
    }

    return mapped;
  }

  void _goToPreviousMonth() {
    setState(() {
      displayedMonth = DateTime(displayedMonth.year, displayedMonth.month - 1);
      if (selectedDate.month != displayedMonth.month ||
          selectedDate.year != displayedMonth.year) {
        selectedDate = DateTime(displayedMonth.year, displayedMonth.month, 1);
      }
    });
  }

  void _goToNextMonth() {
    setState(() {
      displayedMonth = DateTime(displayedMonth.year, displayedMonth.month + 1);
      if (selectedDate.month != displayedMonth.month ||
          selectedDate.year != displayedMonth.year) {
        selectedDate = DateTime(displayedMonth.year, displayedMonth.month, 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final calendarDays = buildCalendarDays(displayedMonth);
    final today = DateTime.now();

    return StreamBuilder<List<AppointmentRecord>>(
      stream: _employeeAppointmentsStream(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Color(0xFFF5F5F5),
            endDrawer: EmployeeMenu(
              employeeName: widget.employeeName,
              employeeId: widget.employeeId,
            ),
            body: SafeArea(
              child: Center(
                child: Text('Something went wrong'),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: Color(0xFFF5F5F5),
            endDrawer: EmployeeMenu(
              employeeName: widget.employeeName,
              employeeId: widget.employeeId,
            ),
            body: SafeArea(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(_calendarHiddenAppointmentsCollection)
              .snapshots(),
          builder: (context, hiddenSnapshot) {
            final hiddenIds = hiddenSnapshot.data?.docs
                .map((doc) => doc.id)
                .toSet() ??
                <String>{};

            final appointments = snapshot.data!
                .where((appointment) => !hiddenIds.contains(appointment.id))
                .toList();

            final sortedAppointments = [...appointments]
              ..sort((a, b) {
                final aDateTime = _appointmentStartDateTime(a);
                final bDateTime = _appointmentStartDateTime(b);

                if (aDateTime != null && bDateTime != null) {
                  return aDateTime.compareTo(bDateTime);
                }
                if (aDateTime != null) return -1;
                if (bDateTime != null) return 1;
                return a.startTime.compareTo(b.startTime);
              });

            final events = mapEvents(sortedAppointments);
            final selectedEvents = [...(events[dateKey(selectedDate)] ?? [])]
              ..sort((a, b) {
                final aDateTime = _appointmentStartDateTime(a);
                final bDateTime = _appointmentStartDateTime(b);

                if (aDateTime != null && bDateTime != null) {
                  return aDateTime.compareTo(bDateTime);
                }
                if (aDateTime != null) return -1;
                if (bDateTime != null) return 1;
                return a.startTime.compareTo(b.startTime);
              });

            return Scaffold(
              endDrawer: EmployeeMenu(
                employeeName: widget.employeeName,
                employeeId: widget.employeeId,
              ),
              backgroundColor: Color(0xFFF5F5F5),
              body: SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Column(
                    children: [
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Spacer(),
                          Text(
                            widget.employeeName,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Spacer(),
                          Builder(
                            builder: (context) => IconButton(
                              icon: Icon(Icons.menu, size: 28),
                              onPressed: () {
                                Scaffold.of(context).openEndDrawer();
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Divider(),
                      SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _CalendarArrowButton(
                            icon: Icons.chevron_left,
                            onTap: _goToPreviousMonth,
                            isDark: false,
                          ),
                          Column(
                            children: [
                              Text(
                                localizedMonthName(context, displayedMonth.month),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${displayedMonth.year}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          _CalendarArrowButton(
                            icon: Icons.chevron_right,
                            onTap: _goToNextMonth,
                            isDark: false,
                          ),
                        ],
                      ),
                      SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(child: Center(child: Text(tr(context, 'Sun'), style: TextStyle(color: Colors.black54, fontSize: 16)))),
                          Expanded(child: Center(child: Text(tr(context, 'Mon'), style: TextStyle(color: Colors.black54, fontSize: 16)))),
                          Expanded(child: Center(child: Text(tr(context, 'Tue'), style: TextStyle(color: Colors.black54, fontSize: 16)))),
                          Expanded(child: Center(child: Text(tr(context, 'Wed'), style: TextStyle(color: Colors.black54, fontSize: 16)))),
                          Expanded(child: Center(child: Text(tr(context, 'Thu'), style: TextStyle(color: Colors.black54, fontSize: 16)))),
                          Expanded(child: Center(child: Text(tr(context, 'Fri'), style: TextStyle(color: Colors.black54, fontSize: 16)))),
                          Expanded(child: Center(child: Text(tr(context, 'Sat'), style: TextStyle(color: Colors.black54, fontSize: 16)))),
                        ],
                      ),
                      SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: calendarDays.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                                SizedBox(height: 4),
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
                                  SizedBox(height: 5),
                              ],
                            ),
                          );
                        },
                      ),
                      Divider(),
                      SizedBox(height: 10),
                      Expanded(
                        child: selectedEvents.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.event_note_rounded,
                                size: 42,
                                color: Colors.black38,
                              ),
                              SizedBox(height: 12),
                              Text(
                                noEventsForDate(context, selectedDate),
                                style: TextStyle(
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
                          separatorBuilder: (_, _) => SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final event = selectedEvents[index];

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  showEmployeeEventPopup(
                                    context,
                                    appointment: event,
                                  );
                                },
                                child: Container(
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kEmployeeEventColor,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${event.startTime}-${event.endTime}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        event.title,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (event.notes.trim().isNotEmpty) ...[
                                        SizedBox(height: 6),
                                        Text(
                                          event.notes,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
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
          },
        );
      },
    );
  }
}

class _CalendarArrowButton extends StatelessWidget {
  const _CalendarArrowButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
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
            color: isDark ? Color(0xFF2A2A2A) : Color(0xFFD7D7D7),
          ),
          borderRadius: BorderRadius.circular(14),
          color: isDark ? Color(0xFF171717) : Colors.white,
        ),
        child: Icon(
          icon,
          size: 24,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}

Future<void> showEmployeeEventPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
    }) async {
  final eventNameController = TextEditingController(
    text: appointment.title,
  );
  final dateController = TextEditingController(
    text: appointment.date,
  );
  final startTimeController = TextEditingController(
    text: appointment.startTime,
  );
  final endTimeController = TextEditingController(
    text: appointment.endTime,
  );
  final clientController = TextEditingController(
    text: '${appointment.clientName} (${appointment.clientPhone})',
  );
  final addressController = TextEditingController(
    text: appointment.address,
  );
  final noteController = TextEditingController(
    text: appointment.notes,
  );
  final materialsController = TextEditingController(
    text: appointment.materialsNeeded,
  );
  final picturesController = TextEditingController(
    text: appointment.pictures,
  );

  final hasStarted = _hasAppointmentStarted(appointment);

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
            decoration: BoxDecoration(
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
                            color: Color(0xFFD0D0D0),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Center(
                        child: Text(
                          tr(context, 'Event'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      SizedBox(height: 18),
                      _popupTextField(
                        controller: eventNameController,
                        hintText: tr(context, 'Event name'),
                        readOnly: true,
                      ),
                      SizedBox(height: 14),
                      _popupTextField(
                        controller: dateController,
                        hintText: tr(context, 'Date'),
                        suffixIcon: Icons.calendar_today_outlined,
                        readOnly: true,
                      ),
                      SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _popupTextField(
                              controller: startTimeController,
                              hintText: tr(context, 'Start Time'),
                              suffixIcon: Icons.access_time_outlined,
                              readOnly: true,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _popupTextField(
                              controller: endTimeController,
                              hintText: tr(context, 'End Time'),
                              suffixIcon: Icons.access_time_outlined,
                              readOnly: true,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14),
                      GestureDetector(
                        onTap: () async {
                          await _openClientDetailsForAppointment(
                            context,
                            appointment,
                            isDark: false,
                          );
                        },
                        child: AbsorbPointer(
                          child: _popupTextField(
                            controller: clientController,
                            hintText: tr(context, 'Client name (phone number)'),
                            readOnly: true,
                            suffixIcon: Icons.person_outline,
                          ),
                        ),
                      ),
                      SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          final address = addressController.text.trim();
                          if (address.isNotEmpty) {
                            openMapsOptions(context, address);
                          }
                        },
                        child: AbsorbPointer(
                          child: _popupTextField(
                            controller: addressController,
                            hintText: tr(context, 'Address'),
                            readOnly: true,
                            suffixIcon: Icons.map,
                          ),
                        ),
                      ),
                      SizedBox(height: 14),
                      FutureBuilder<_AttachedEmployeesInfo>(
                        future: _loadAttachedEmployeesInfo(appointment),
                        builder: (context, snapshot) {
                          final employeesText = snapshot.data?.displayText(context) ??
                              _employeesAttachedText(appointment, context);

                          return _popupTextField(
                            controller: TextEditingController(text: employeesText),
                            hintText: tr(context, 'Employees attached'),
                            readOnly: true,
                            maxLines: 3,
                            suffixIcon: Icons.people_outline,
                          );
                        },
                      ),
                      SizedBox(height: 14),
                      _popupTextField(
                        controller: noteController,
                        hintText: tr(context, 'Notes'),
                        suffixIcon: Icons.note_alt_outlined,
                        maxLines: 3,
                        readOnly: true,
                      ),
                      SizedBox(height: 14),
                      _popupTextField(
                        controller: materialsController,
                        hintText: tr(context, 'Materials needed'),
                        suffixIcon: Icons.build_outlined,
                        maxLines: 3,
                        readOnly: true,
                      ),
                      SizedBox(height: 14),
                      _popupTextField(
                        controller: picturesController,
                        hintText: tr(context, 'Pictures'),
                        suffixIcon: Icons.image_outlined,
                        maxLines: 3,
                        readOnly: true,
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (hasStarted) {
                              await _markAppointmentDoneForCalendar(appointment);
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPurple,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            tr(context, hasStarted ? 'Event Done' : 'Close'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
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
      hintStyle: TextStyle(
        color: Color(0xFF7A7A7A),
        fontSize: 15,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 16,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kPurple),
      ),
      suffixIcon: suffixIcon != null
          ? Icon(suffixIcon, color: Color(0xFF7A7A7A))
          : null,
    ),
  );
}

class EmployeeCalendarDarkPage extends StatefulWidget {
  const EmployeeCalendarDarkPage({
    super.key,
    required this.employeeId,
    this.employeeName = 'Employee name',
  });

  final String employeeId;
  final String employeeName;

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

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

  Map<String, List<AppointmentRecord>> _eventsByDate(
      List<AppointmentRecord> appointments,
      ) {
    final map = <String, List<AppointmentRecord>>{};
    for (final appointment in appointments) {
      final parsedDate = _parseDisplayDate(appointment.date);
      if (parsedDate == null) continue;

      final key = _dateKey(parsedDate);
      map.putIfAbsent(key, () => []);
      map[key]!.add(appointment);
    }
    return map;
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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _goToPreviousMonth() {
    setState(() {
      displayedMonth = DateTime(displayedMonth.year, displayedMonth.month - 1);
      if (selectedDate.month != displayedMonth.month ||
          selectedDate.year != displayedMonth.year) {
        selectedDate = DateTime(displayedMonth.year, displayedMonth.month, 1);
      }
    });
  }

  void _goToNextMonth() {
    setState(() {
      displayedMonth = DateTime(displayedMonth.year, displayedMonth.month + 1);
      if (selectedDate.month != displayedMonth.month ||
          selectedDate.year != displayedMonth.year) {
        selectedDate = DateTime(displayedMonth.year, displayedMonth.month, 1);
      }
    });
  }

  void _showEventPopup(AppointmentRecord event) {
    final hasStarted = _hasAppointmentStarted(event);

    showModalBottomSheet(
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
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: Color(0xFF2A2A2A)),
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
                              color: Color(0xFF3A3A3A),
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        Center(
                          child: Text(
                            tr(context, 'Event'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(height: 18),
                        _buildDarkField(event.title),
                        SizedBox(height: 12),
                        _buildDarkField(
                          event.date,
                          icon: Icons.calendar_today_outlined,
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDarkField(
                                event.startTime,
                                icon: Icons.access_time_outlined,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _buildDarkField(
                                event.endTime,
                                icon: Icons.access_time_outlined,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            await _openClientDetailsForAppointment(
                              context,
                              event,
                              isDark: true,
                            );
                          },
                          child: _buildDarkField(
                            '${event.clientName} (${event.clientPhone})',
                            icon: Icons.person_outline,
                          ),
                        ),
                        SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            final address = event.address.trim();
                            if (address.isNotEmpty) {
                              openMapsOptions(context, address);
                            }
                          },
                          child: _buildDarkField(
                            event.address,
                            icon: Icons.map,
                          ),
                        ),
                        SizedBox(height: 12),
                        FutureBuilder<_AttachedEmployeesInfo>(
                          future: _loadAttachedEmployeesInfo(event),
                          builder: (context, snapshot) {
                            final employeesText = snapshot.data?.displayText(context) ??
                                _employeesAttachedText(event, context);

                            return _buildDarkLargeField(
                              employeesText,
                              icon: Icons.people_outline,
                            );
                          },
                        ),
                        SizedBox(height: 12),
                        _buildDarkLargeField(
                          event.notes.isEmpty
                              ? tr(context, 'Notes')
                              : event.notes,
                          icon: Icons.description_outlined,
                        ),
                        SizedBox(height: 12),
                        _buildDarkLargeField(
                          event.materialsNeeded.isEmpty
                              ? tr(context, 'Materials needed')
                              : event.materialsNeeded,
                          icon: Icons.build_outlined,
                        ),
                        SizedBox(height: 12),
                        _buildDarkLargeField(
                          event.pictures.isEmpty
                              ? tr(context, 'Pictures')
                              : event.pictures,
                          icon: Icons.image_outlined,
                        ),
                        SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () async {
                              if (hasStarted) {
                                await _markAppointmentDoneForCalendar(event);
                              }
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: Text(
                              tr(context, hasStarted ? 'Event Done' : 'Close'),
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDarkField(String text, {IconData? icon}) {
    return Container(
      height: 52,
      padding: EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3A3A3A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
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

  Widget _buildDarkLargeField(String text, {IconData? icon}) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: 84),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3A3A3A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
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

    return StreamBuilder<List<AppointmentRecord>>(
      stream: _employeeAppointmentsStream(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.black,
            endDrawer: EmployeeMenu(
              employeeName: widget.employeeName,
              employeeId: widget.employeeId,
            ),
            body: SafeArea(
              child: Center(
                child: Text(
                  'Something went wrong',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: Colors.black,
            endDrawer: EmployeeMenuDark(
              employeeName: widget.employeeName,
              employeeId: widget.employeeId,
            ),
            body: SafeArea(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(_calendarHiddenAppointmentsCollection)
              .snapshots(),
          builder: (context, hiddenSnapshot) {
            final hiddenIds = hiddenSnapshot.data?.docs
                .map((doc) => doc.id)
                .toSet() ??
                <String>{};

            final appointments = snapshot.data!
                .where((appointment) => !hiddenIds.contains(appointment.id))
                .toList();

            final sortedAppointments = [...appointments]
              ..sort((a, b) {
                final aDateTime = _appointmentStartDateTime(a);
                final bDateTime = _appointmentStartDateTime(b);

                if (aDateTime != null && bDateTime != null) {
                  return aDateTime.compareTo(bDateTime);
                }
                if (aDateTime != null) return -1;
                if (bDateTime != null) return 1;
                return a.startTime.compareTo(b.startTime);
              });

            final eventsByDate = _eventsByDate(sortedAppointments);
            final selectedEvents = [...(eventsByDate[_dateKey(selectedDate)] ?? [])]
              ..sort((a, b) {
                final aDateTime = _appointmentStartDateTime(a);
                final bDateTime = _appointmentStartDateTime(b);

                if (aDateTime != null && bDateTime != null) {
                  return aDateTime.compareTo(bDateTime);
                }
                if (aDateTime != null) return -1;
                if (bDateTime != null) return 1;
                return a.startTime.compareTo(b.startTime);
              });

            return Scaffold(
              backgroundColor: Colors.black,
              endDrawer: EmployeeMenuDark(
                employeeName: widget.employeeName,
                employeeId: widget.employeeId,
              ),
              body: SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Spacer(),
                          Text(
                            widget.employeeName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Spacer(),
                          Builder(
                            builder: (context) => IconButton(
                              icon: Icon(
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
                      Divider(color: Color(0xFF2A2A2A), height: 18),
                      SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _CalendarArrowButton(
                            icon: Icons.chevron_left,
                            onTap: _goToPreviousMonth,
                            isDark: true,
                          ),
                          Column(
                            children: [
                              Text(
                                localizedMonthName(context, displayedMonth.month),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                displayedMonth.year.toString(),
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          _CalendarArrowButton(
                            icon: Icons.chevron_right,
                            onTap: _goToNextMonth,
                            isDark: true,
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Center(child: Text(tr(context, 'Sun'), style: WeekdayStyle()))),
                          Expanded(child: Center(child: Text(tr(context, 'Mon'), style: WeekdayStyle()))),
                          Expanded(child: Center(child: Text(tr(context, 'Tue'), style: WeekdayStyle()))),
                          Expanded(child: Center(child: Text(tr(context, 'Wed'), style: WeekdayStyle()))),
                          Expanded(child: Center(child: Text(tr(context, 'Thu'), style: WeekdayStyle()))),
                          Expanded(child: Center(child: Text(tr(context, 'Fri'), style: WeekdayStyle()))),
                          Expanded(child: Center(child: Text(tr(context, 'Sat'), style: WeekdayStyle()))),
                        ],
                      ),
                      SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: calendarDays.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                                SizedBox(height: 4),
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
                                  SizedBox(height: 5),
                              ],
                            ),
                          );
                        },
                      ),
                      Divider(color: Color(0xFF2A2A2A), height: 24),
                      Expanded(
                        child: selectedEvents.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 40,
                                color: Colors.white38,
                              ),
                              SizedBox(height: 10),
                              Text(
                                noEventsForDate(context, selectedDate, monthFirst: true),
                                style: TextStyle(
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
                          separatorBuilder: (_, _) => SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final event = selectedEvents[index];

                            return GestureDetector(
                              onTap: () => _showEventPopup(event),
                              child: Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: kPurple,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${event.startTime}-${event.endTime}',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      event.title,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
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
          },
        );
      },
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

Future<void> openMapsOptions(BuildContext context, String address) async {
  final encodedAddress = Uri.encodeComponent(address);

  final googleMapsUrl = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$encodedAddress',
  );

  final appleMapsUrl = Uri.parse(
    'https://maps.apple.com/?q=$encodedAddress',
  );

  final wazeUrl = Uri.parse(
    'https://waze.com/ul?q=$encodedAddress&navigate=yes',
  );

  await showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isIOS)
              ListTile(
                leading: Icon(Icons.map),
                title: Text('Apple Maps'),
                onTap: () async {
                  Navigator.pop(context);
                  await launchUrl(
                    appleMapsUrl,
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.map_outlined),
              title: Text('Google Maps'),
              onTap: () async {
                Navigator.pop(context);
                await launchUrl(
                  googleMapsUrl,
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.navigation),
              title: Text('Waze'),
              onTap: () async {
                Navigator.pop(context);
                await launchUrl(
                  wazeUrl,
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
