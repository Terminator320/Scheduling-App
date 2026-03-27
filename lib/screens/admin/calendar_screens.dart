import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

import '../../models/appointment_record.dart';
import '../../models/client_record.dart';
import '../../models/employee_record.dart';
import '../../services/appointment_service.dart';
import '../../services/client_service.dart';
import '../../services/google_places_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../../utils/colors.dart';
import '../../widgets/admin_drawers.dart';
import 'clients_screens.dart';


Future<String> _loggedInEmployeeName(List<EmployeeRecord> employees) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    return 'User';
  }

  final authUid = user.uid.trim();
  final authEmail = (user.email ?? '').trim().toLowerCase();

  // ✅ First: try employees list (fast)
  for (final employee in employees) {
    final employeeUid = employee.uid.trim();
    final employeeEmail = employee.email.trim().toLowerCase();
    final employeeName = employee.name.trim();

    if (authUid.isNotEmpty && employeeUid == authUid) {
      return employeeName.isNotEmpty ? employeeName : 'User';
    }

    if (authEmail.isNotEmpty && employeeEmail == authEmail) {
      return employeeName.isNotEmpty ? employeeName : 'User';
    }
  }

  // 🔥 Second: fallback → search ALL users (for admin)
  final result = await FirebaseFirestore.instance
      .collection('users')
      .where('uid', isEqualTo: authUid)
      .limit(1)
      .get();

  if (result.docs.isNotEmpty) {
    final data = result.docs.first.data();
    final name = (data['name'] ?? '').toString().trim();

    if (name.isNotEmpty) return name;
  }

  return 'User';
}

class AdminCalendarPage extends StatefulWidget {
  const AdminCalendarPage({super.key});

  @override
  State<AdminCalendarPage> createState() => _AdminCalendarPageState();
}

class _AdminCalendarPageState extends State<AdminCalendarPage> {
  DateTime displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();

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

  void _openAddEventPopup() {
    showAddEventPopup(context, selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final calendarDays = buildCalendarDays(displayedMonth);
    final today = DateTime.now();

    return StreamBuilder<List<EmployeeRecord>>(
      stream: UserService.employeesStream(),
      builder: (context, employeeSnapshot) {
        final employees = _normalizeEmployees(employeeSnapshot.data ?? []);

        return StreamBuilder<List<AppointmentRecord>>(
          stream: AppointmentService.appointmentsStream(),
          builder: (context, snapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(_calendarHiddenAppointmentsCollection)
                  .snapshots(),
              builder: (context, hiddenSnapshot) {
                final hiddenIds = hiddenSnapshot.data?.docs
                    .map((doc) => doc.id)
                    .toSet() ??
                    <String>{};
                final appointments = (snapshot.data ?? [])
                    .where((a) => !hiddenIds.contains(a.id))
                    .toList();
                final selectedEvents = appointments
                    .where((a) => _sameDateString(a.date, dateKey(selectedDate)))
                    .toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));

                return Scaffold(
                  backgroundColor: Color(0xFFF5F5F5),
                  endDrawer: AdminMenuDrawer(),
                  floatingActionButton: FloatingActionButton(
                    onPressed: _openAddEventPopup,
                    backgroundColor: kPurple,
                    shape: CircleBorder(),
                    child: Icon(Icons.add, color: Colors.white, size: 30),
                  ),
                  body: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Column(
                        children: [
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Spacer(),
                              FutureBuilder<String>(
                                future: _loggedInEmployeeName(employees),
                                builder: (context, snapshot) {
                                  final name = snapshot.data ?? 'User';

                                  return Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),
                              Spacer(),
                              Builder(
                                builder: (context) => GestureDetector(
                                  onTap: () => Scaffold.of(context).openEndDrawer(),
                                  child: Icon(Icons.menu, size: 28),
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
                              final dayAppointments = appointments
                                  .where((a) => _sameDateString(a.date, dateKey(day)))
                                  .toList();
                              final hasEvents = dayAppointments.isNotEmpty;

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
                                      _calendarEventDots(
                                        dayAppointments,
                                        employees: employees,
                                        isDark: false,
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
                            child: snapshot.hasError
                                ? Center(
                              child: Text(tr(context, 'Something went wrong')),
                            )
                                : selectedEvents.isEmpty
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
                                  SizedBox(height: 8),
                                  Text(
                                    tr(context, 'Tap the + button to add one later.'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            )
                                : ListView.separated(
                              itemCount: selectedEvents.length,
                              separatorBuilder: (_, _) => SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final event = selectedEvents[index];
                                final employeeColor = _appointmentEmployeeColor(
                                  event,
                                  employees: employees,
                                  isDark: false,
                                );
                                final employeeName = _appointmentEmployeeName(event);

                                return Container(
                                  decoration: BoxDecoration(
                                    color: _appointmentCardColor(
                                      event,
                                      employeeColor: employeeColor,
                                      isDark: false,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(20),
                                            onTap: () async {
                                              await showCalendarEventDetailsPopup(
                                                context,
                                                appointment: event,
                                                employeeColor: employeeColor,
                                                employees: employees,
                                              );
                                            },
                                            child: Padding(
                                              padding: EdgeInsets.fromLTRB(16, 16, 8, 16),
                                              child: Builder(
                                                builder: (context) {
                                                  final clientLine = _appointmentClientLine(event);

                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '${event.startTime} - ${event.endTime}',
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
                                                      if (employeeName.isNotEmpty) ...[
                                                        SizedBox(height: 8),
                                                        _appointmentAssignedEmployeesRow(
                                                          employeeName: employeeName,
                                                          employees: employees,
                                                          isDark: false,
                                                        ),
                                                      ],
                                                      if (clientLine.isNotEmpty) ...[
                                                        SizedBox(height: 6),
                                                        Text(
                                                          clientLine,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            color: Colors.black54,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.fromLTRB(0, 10, 10, 0),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: () async {
                                            await showEditCalendarEventPopup(
                                              context,
                                              appointment: event,
                                            );
                                            if (context.mounted) {
                                              setState(() {});
                                            }
                                          },
                                          child: Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Icon(
                                              Icons.more_horiz,
                                              color: Colors.black54,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
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
              },
            );
          },
        );
      },
    );
  }
}

class _CalendarArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CalendarArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          border: Border.all(color: Color(0xFFD7D7D7)),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
        ),
        child: Icon(icon, size: 24),
      ),
    );
  }
}

/* ---------------- ADMIN CALENDAR PAGE DARK ---------------- */

class AdminCalendarDarkPage extends StatefulWidget {
  const AdminCalendarDarkPage({super.key});

  @override
  State<AdminCalendarDarkPage> createState() => _AdminCalendarDarkPageState();
}

class _AdminCalendarDarkPageState extends State<AdminCalendarDarkPage> {
  DateTime displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();

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

  void _openAddEventPopup() {
    showAddEventDarkPopup(context, selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    const background = Colors.black;
    const primaryText = Colors.white;
    const secondaryText = Color(0xFF9E9E9E);
    const fadedText = Color(0xFF5F5F5F);
    const dividerColor = Color(0xFF3A3A3A);

    final calendarDays = buildCalendarDays(displayedMonth);
    final today = DateTime.now();

    return StreamBuilder<List<EmployeeRecord>>(
      stream: UserService.employeesStream(),
      builder: (context, employeeSnapshot) {
        final employees = _normalizeEmployees(employeeSnapshot.data ?? []);

        return StreamBuilder<List<AppointmentRecord>>(
          stream: AppointmentService.appointmentsStream(),
          builder: (context, snapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(_calendarHiddenAppointmentsCollection)
                  .snapshots(),
              builder: (context, hiddenSnapshot) {
                final hiddenIds = hiddenSnapshot.data?.docs
                    .map((doc) => doc.id)
                    .toSet() ??
                    <String>{};
                final appointments = (snapshot.data ?? [])
                    .where((a) => !hiddenIds.contains(a.id))
                    .toList();
                final selectedEvents = appointments
                    .where((a) => _sameDateString(a.date, dateKey(selectedDate)))
                    .toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));

                return Scaffold(
                  backgroundColor: background,
                  endDrawer: AdminMenuDrawerDark(),
                  floatingActionButton: FloatingActionButton(
                    onPressed: _openAddEventPopup,
                    backgroundColor: kPurple,
                    shape: CircleBorder(),
                    child: Icon(Icons.add, color: Colors.white, size: 30),
                  ),
                  body: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Column(
                        children: [
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Spacer(),
                              FutureBuilder<String>(
                                future: _loggedInEmployeeName(employees),
                                builder: (context, snapshot) {
                                  final name = snapshot.data ?? 'User';

                                  return Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),
                              Spacer(),
                              Builder(
                                builder: (context) => GestureDetector(
                                  onTap: () => Scaffold.of(context).openEndDrawer(),
                                  child: Icon(Icons.menu, size: 28, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Divider(color: dividerColor),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _CalendarDarkArrowButton(
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
                                    localizedMonthName(context, displayedMonth.month),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: primaryText,
                                    ),
                                  ),
                                  Text(
                                    '${displayedMonth.year}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                              _CalendarDarkArrowButton(
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
                          SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(child: Center(child: Text(tr(context, 'Sun'), style: TextStyle(color: secondaryText, fontSize: 16)))),
                              Expanded(child: Center(child: Text(tr(context, 'Mon'), style: TextStyle(color: secondaryText, fontSize: 16)))),
                              Expanded(child: Center(child: Text(tr(context, 'Tue'), style: TextStyle(color: secondaryText, fontSize: 16)))),
                              Expanded(child: Center(child: Text(tr(context, 'Wed'), style: TextStyle(color: secondaryText, fontSize: 16)))),
                              Expanded(child: Center(child: Text(tr(context, 'Thu'), style: TextStyle(color: secondaryText, fontSize: 16)))),
                              Expanded(child: Center(child: Text(tr(context, 'Fri'), style: TextStyle(color: secondaryText, fontSize: 16)))),
                              Expanded(child: Center(child: Text(tr(context, 'Sat'), style: TextStyle(color: secondaryText, fontSize: 16)))),
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
                              final dayAppointments = appointments
                                  .where((a) => _sameDateString(a.date, dateKey(day)))
                                  .toList();
                              final hasEvents = dayAppointments.isNotEmpty;

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
                                              ? Colors.white
                                              : fadedText,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    if (hasEvents)
                                      _calendarEventDots(
                                        dayAppointments,
                                        employees: employees,
                                        isDark: true,
                                      )
                                    else
                                      SizedBox(height: 5),
                                  ],
                                ),
                              );
                            },
                          ),
                          SizedBox(height: 18),
                          Expanded(
                            child: snapshot.hasError
                                ? Center(
                              child: Text(
                                tr(context, 'Something went wrong'),
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                                : selectedEvents.isEmpty
                                ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.event_note_rounded,
                                    size: 42,
                                    color: fadedText,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    noEventsForDate(context, selectedDate),
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: secondaryText,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    tr(context, 'Tap the + button to add one later.'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: fadedText,
                                    ),
                                  ),
                                ],
                              ),
                            )
                                : ListView.separated(
                              itemCount: selectedEvents.length,
                              separatorBuilder: (_, _) => SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final event = selectedEvents[index];
                                final employeeColor = _appointmentEmployeeColor(
                                  event,
                                  employees: employees,
                                  isDark: true,
                                );
                                final employeeName = _appointmentEmployeeName(event);

                                return Container(
                                  decoration: BoxDecoration(
                                    color: _appointmentCardColor(
                                      event,
                                      employeeColor: employeeColor,
                                      isDark: true,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(20),
                                            onTap: () async {
                                              await showCalendarEventDetailsDarkPopup(
                                                context,
                                                appointment: event,
                                                employeeColor: employeeColor,
                                                employees: employees,
                                              );
                                            },
                                            child: Padding(
                                              padding: EdgeInsets.fromLTRB(16, 16, 8, 16),
                                              child: Builder(
                                                builder: (context) {
                                                  final clientLine = _appointmentClientLine(event);

                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '${event.startTime} - ${event.endTime}',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color: Color(0xFFD8CFFF),
                                                        ),
                                                      ),
                                                      SizedBox(height: 8),
                                                      Text(
                                                        event.title,
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.w600,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      if (employeeName.isNotEmpty) ...[
                                                        SizedBox(height: 8),
                                                        _appointmentAssignedEmployeesRow(
                                                          employeeName: employeeName,
                                                          employees: employees,
                                                          isDark: true,
                                                        ),
                                                      ],
                                                      if (clientLine.isNotEmpty) ...[
                                                        SizedBox(height: 6),
                                                        Text(
                                                          clientLine,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            color: Color(0xFFE7DFFF),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.fromLTRB(0, 10, 10, 0),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: () async {
                                            await showEditCalendarEventDarkPopup(
                                              context,
                                              appointment: event,
                                            );
                                            if (context.mounted) {
                                              setState(() {});
                                            }
                                          },
                                          child: Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Icon(
                                              Icons.more_horiz,
                                              color: Color(0xFFE7DFFF),
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
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
              },
            );
          },
        );
      },
    );
  }
}

class _CalendarDarkArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CalendarDarkArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          border: Border.all(color: Color(0xFF4A4A4A)),
          borderRadius: BorderRadius.circular(14),
          color: Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 24,
          color: Colors.white,
        ),
      ),
    );
  }
}


String _clientDisplayNameFromRecord(ClientRecord client) {
  final businessName = (client.businessName ?? '').trim();
  final name = client.name.trim();

  if (businessName.isNotEmpty) return businessName;
  return name;
}

String _clientDisplayContactFromRecord(ClientRecord client) {
  final phone = client.phone.trim();
  final email = client.email.trim();

  if (phone.isNotEmpty) return phone;
  return email;
}

String _addressSuggestionText(dynamic suggestion) {
  try {
    final fullAddress = (suggestion.fullAddress ?? '').toString().trim();
    if (fullAddress.isNotEmpty) return fullAddress;
  } catch (_) {}

  try {
    final description = (suggestion.description ?? '').toString().trim();
    if (description.isNotEmpty) return description;
  } catch (_) {}

  try {
    final mainText = (suggestion.mainText ?? '').toString().trim();
    if (mainText.isNotEmpty) return mainText;
  } catch (_) {}

  return suggestion.toString().trim();
}

/* ---------------- ADD EVENT LIGHT ---------------- */

Future<void> showAddEventPopup(
    BuildContext context,
    DateTime selectedDate,
    ) async {
  final TextEditingController eventNameController = TextEditingController();
  final TextEditingController dateController = TextEditingController(
    text: _formatDateKey(selectedDate),
  );
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();
  final TextEditingController clientController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController materialsController = TextEditingController();
  final TextEditingController picturesController = TextEditingController();

  final Set<String> selectedEmployeeIds = <String>{};
  List<EmployeeRecord> availableEmployees = [];
  ClientRecord? selectedClient;
  List<ClientRecord> clientResults = [];
  List<dynamic> addressResults = [];
  bool isSearchingAddresses = false;
  bool isSaving = false;
  String? popupError;

  Future<void> searchClients(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        clientResults = [];
        selectedClient = null;
      });
      return;
    }

    final results = await ClientService.searchClients(query);

    setPopupState(() {
      clientResults = results;
    });
  }

  Future<void> searchAddresses(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
      return;
    }

    setPopupState(() {
      isSearchingAddresses = true;
    });

    try {
      final results = await GooglePlacesService.autocomplete(query);

      setPopupState(() {
        addressResults = List<dynamic>.from(results);
        isSearchingAddresses = false;
      });
    } catch (_) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
    }
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setPopupState) {
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
                              tr(context, 'Add New Event'),
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
                            hintText: tr(context, 'Event name *'),
                            onChanged: (_) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                            },
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: dateController,
                            hintText: tr(context, 'Date *'),
                            suffixIcon: Icons.calendar_today_outlined,
                            onChanged: (_) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                            },
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextField(
                                  controller: startTimeController,
                                  hintText: tr(context, 'Start Time *'),
                                  suffixIcon: Icons.access_time_outlined,
                                  onChanged: (_) {
                                    if (popupError != null) {
                                      setPopupState(() {
                                        popupError = null;
                                      });
                                    }
                                  },
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextField(
                                  controller: endTimeController,
                                  hintText: tr(context, 'End Time'),
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: clientController,
                            hintText: tr(context, 'Client * (search by name or phone number)'),
                            onChanged: (value) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                              searchClients(value, setPopupState);
                            },
                          ),
                          if (clientResults.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Container(
                              constraints: BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFFD8D8D8)),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: clientResults.length,
                                itemBuilder: (context, index) {
                                  final client = clientResults[index];
                                  return ListTile(
                                    title: Text(_clientDisplayNameFromRecord(client)),
                                    subtitle: Text(_clientDisplayContactFromRecord(client)),
                                    onTap: () {
                                      setPopupState(() {
                                        selectedClient = client;
                                        clientController.text = _clientDisplayNameFromRecord(client);
                                        addressController.text = client.address;
                                        clientResults = [];
                                        addressResults = [];
                                        popupError = null;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          if (selectedClient != null) ...[
                            SizedBox(height: 8),
                            Text(
                              '${_clientDisplayNameFromRecord(selectedClient!)} (${_clientDisplayContactFromRecord(selectedClient!)})',
                              style: TextStyle(fontSize: 13, color: Colors.black54),
                            ),
                            SizedBox(height: 14),
                            _popupTextField(
                              controller: addressController,
                              hintText: tr(context, 'Address *'),
                              suffixIcon: Icons.map_outlined,
                              onChanged: (value) {
                                if (popupError != null) {
                                  setPopupState(() {
                                    popupError = null;
                                  });
                                }
                                searchAddresses(value, setPopupState);
                              },
                            ),
                            if (isSearchingAddresses) ...[
                              SizedBox(height: 8),
                              Center(child: CircularProgressIndicator()),
                            ] else if (addressResults.isNotEmpty) ...[
                              SizedBox(height: 8),
                              Container(
                                constraints: BoxConstraints(maxHeight: 180),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Color(0xFFD8D8D8)),
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: addressResults.length,
                                  itemBuilder: (context, index) {
                                    final suggestion = addressResults[index];
                                    final suggestionText =
                                    _addressSuggestionText(suggestion);

                                    return ListTile(
                                      title: Text(suggestionText),
                                      onTap: () {
                                        setPopupState(() {
                                          addressController.text = suggestionText;
                                          addressResults = [];
                                          popupError = null;
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: noteController,
                            hintText: tr(context, 'Type the note here...'),
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: materialsController,
                            hintText: tr(context, 'Type the materials here...'),
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: picturesController,
                            hintText: tr(context, 'Insert pictures here...'),
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          StreamBuilder<List<EmployeeRecord>>(
                            stream: UserService.employeesStream(),
                            builder: (context, snapshot) {
                              final employees = _normalizeEmployees(snapshot.data ?? []);

                              availableEmployees = employees;

                              if (snapshot.connectionState == ConnectionState.waiting &&
                                  employees.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              return _employeeSelectorLight(
                                context: context,
                                employees: employees,
                                selectedEmployeeIds: selectedEmployeeIds,
                                onSelected: (employeeId) {
                                  setPopupState(() {
                                    if (selectedEmployeeIds.contains(employeeId)) {
                                      selectedEmployeeIds.remove(employeeId);
                                    } else {
                                      selectedEmployeeIds.add(employeeId);
                                    }
                                    popupError = null;
                                  });
                                },
                              );
                            },
                          ),
                          SizedBox(height: 16),
                          if (popupError != null) ...[
                            _popupInlineErrorLight(popupError!),
                            SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                if (eventNameController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Event name is required');
                                  });
                                  return;
                                }

                                if (dateController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Date is required');
                                  });
                                  return;
                                }

                                if (startTimeController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Start time is required');
                                  });
                                  return;
                                }

                                if (selectedEmployeeIds.isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Please select at least one employee');
                                  });
                                  return;
                                }

                                if (selectedClient == null) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Please select a client');
                                  });
                                  return;
                                }

                                if (addressController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Address is required');
                                  });
                                  return;
                                }

                                setPopupState(() {
                                  popupError = null;
                                  isSaving = true;
                                });

                                try {
                                  final selectedEmployees = _selectedEmployeesFromIds(
                                    selectedEmployeeIds,
                                    availableEmployees,
                                  );

                                  await AppointmentService.addAppointment(
                                    title: eventNameController.text.trim(),
                                    date: _normalizeDate(dateController.text.trim()),
                                    startTime: _normalizeTimeInput(startTimeController.text.trim()),
                                    endTime: _normalizeEndTimeInput(
                                      start: startTimeController.text.trim(),
                                      end: endTimeController.text.trim(),
                                    ),
                                    clientId: selectedClient!.id,
                                    clientName: selectedClient!.name,
                                    clientPhone: _clientDisplayContactFromRecord(selectedClient!),
                                    employeeId: _joinStoredValues(
                                      selectedEmployees.map((employee) => employee.id),
                                    ),
                                    employeeName: _joinStoredValues(
                                      selectedEmployees.map((employee) => employee.name),
                                    ),
                                    address: addressController.text.trim(),
                                    notes: noteController.text.trim(),
                                    materialsNeeded: materialsController.text.trim(),
                                    pictures: picturesController.text.trim(),
                                  );

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                } catch (e) {
                                  setPopupState(() {
                                    isSaving = false;
                                    popupError = 'Error: $e';
                                  });
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
                                isSaving ? tr(context, 'Saving...') : tr(context, 'Create Event'),
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
    },
  );
}

/* ---------------- ADD EVENT DARK ---------------- */

Future<void> showAddEventDarkPopup(
    BuildContext context,
    DateTime selectedDate,
    ) async {
  final TextEditingController eventNameController = TextEditingController();
  final TextEditingController dateController = TextEditingController(
    text: _formatDateKey(selectedDate),
  );
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();
  final TextEditingController clientController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController materialsController = TextEditingController();
  final TextEditingController picturesController = TextEditingController();

  final Set<String> selectedEmployeeIds = <String>{};
  List<EmployeeRecord> availableEmployees = [];
  ClientRecord? selectedClient;
  List<ClientRecord> clientResults = [];
  List<dynamic> addressResults = [];
  bool isSearchingAddresses = false;
  bool isSaving = false;
  String? popupError;

  Future<void> searchClients(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        clientResults = [];
        selectedClient = null;
      });
      return;
    }

    final results = await ClientService.searchClients(query);

    setPopupState(() {
      clientResults = results;
    });
  }

  Future<void> searchAddresses(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
      return;
    }

    setPopupState(() {
      isSearchingAddresses = true;
    });

    try {
      final results = await GooglePlacesService.autocomplete(query);

      setPopupState(() {
        addressResults = List<dynamic>.from(results);
        isSearchingAddresses = false;
      });
    } catch (_) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
    }
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setPopupState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
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
                                color: Color(0xFF3A3A3A),
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
                          Center(
                            child: Text(
                              tr(context, 'Add New Event'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(height: 18),
                          _popupTextFieldDark(
                            controller: eventNameController,
                            hintText: tr(context, 'Event name *'),
                            onChanged: (_) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                            },
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: dateController,
                            hintText: tr(context, 'Date *'),
                            suffixIcon: Icons.calendar_today_outlined,
                            onChanged: (_) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                            },
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: startTimeController,
                                  hintText: tr(context, 'Start Time *'),
                                  suffixIcon: Icons.access_time_outlined,
                                  onChanged: (_) {
                                    if (popupError != null) {
                                      setPopupState(() {
                                        popupError = null;
                                      });
                                    }
                                  },
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: endTimeController,
                                  hintText: tr(context, 'End Time'),
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: clientController,
                            hintText: tr(context, 'Client * (search by name or phone number)'),
                            onChanged: (value) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                              searchClients(value, setPopupState);
                            },
                          ),
                          if (clientResults.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Container(
                              constraints: BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Color(0xFF171717),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFF2D2D2D)),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: clientResults.length,
                                itemBuilder: (context, index) {
                                  final client = clientResults[index];
                                  return ListTile(
                                    title: Text(
                                      _clientDisplayNameFromRecord(client),
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    subtitle: Text(
                                      _clientDisplayContactFromRecord(client),
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    onTap: () {
                                      setPopupState(() {
                                        selectedClient = client;
                                        clientController.text = _clientDisplayNameFromRecord(client);
                                        addressController.text = client.address;
                                        clientResults = [];
                                        addressResults = [];
                                        popupError = null;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          if (selectedClient != null) ...[
                            SizedBox(height: 8),
                            Text(
                              '${_clientDisplayNameFromRecord(selectedClient!)} (${_clientDisplayContactFromRecord(selectedClient!)})',
                              style: TextStyle(fontSize: 13, color: Colors.white70),
                            ),
                            SizedBox(height: 14),
                            _popupTextFieldDark(
                              controller: addressController,
                              hintText: tr(context, 'Address *'),
                              suffixIcon: Icons.map_outlined,
                              onChanged: (value) {
                                if (popupError != null) {
                                  setPopupState(() {
                                    popupError = null;
                                  });
                                }
                                searchAddresses(value, setPopupState);
                              },
                            ),
                            if (isSearchingAddresses) ...[
                              SizedBox(height: 8),
                              Center(child: CircularProgressIndicator()),
                            ] else if (addressResults.isNotEmpty) ...[
                              SizedBox(height: 8),
                              Container(
                                constraints: BoxConstraints(maxHeight: 180),
                                decoration: BoxDecoration(
                                  color: Color(0xFF171717),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Color(0xFF2D2D2D)),
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: addressResults.length,
                                  itemBuilder: (context, index) {
                                    final suggestion = addressResults[index];
                                    final suggestionText = _addressSuggestionText(suggestion);

                                    return ListTile(
                                      title: Text(
                                        suggestionText,
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      onTap: () {
                                        setPopupState(() {
                                          addressController.text = suggestionText;
                                          addressResults = [];
                                          popupError = null;
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: noteController,
                            hintText: tr(context, 'Type the note here...'),
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: materialsController,
                            hintText: tr(context, 'Type the materials here...'),
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: picturesController,
                            hintText: tr(context, 'Insert pictures here...'),
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          StreamBuilder<List<EmployeeRecord>>(
                            stream: UserService.employeesStream(),
                            builder: (context, snapshot) {
                              final employees = _normalizeEmployees(snapshot.data ?? []);

                              availableEmployees = employees;

                              if (snapshot.connectionState == ConnectionState.waiting &&
                                  employees.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              return _employeeSelectorDark(
                                context: context,
                                employees: employees,
                                selectedEmployeeIds: selectedEmployeeIds,
                                onSelected: (employeeId) {
                                  setPopupState(() {
                                    if (selectedEmployeeIds.contains(employeeId)) {
                                      selectedEmployeeIds.remove(employeeId);
                                    } else {
                                      selectedEmployeeIds.add(employeeId);
                                    }
                                    popupError = null;
                                  });
                                },
                              );
                            },
                          ),
                          SizedBox(height: 16),
                          if (popupError != null) ...[
                            _popupInlineErrorDark(popupError!),
                            SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                if (eventNameController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Event name is required');
                                  });
                                  return;
                                }

                                if (dateController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Date is required');
                                  });
                                  return;
                                }

                                if (startTimeController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Start time is required');
                                  });
                                  return;
                                }

                                if (selectedEmployeeIds.isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Please select at least one employee');
                                  });
                                  return;
                                }

                                if (selectedClient == null) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Please select a client');
                                  });
                                  return;
                                }

                                if (addressController.text.trim().isEmpty) {
                                  setPopupState(() {
                                    popupError = tr(context, 'Address is required');
                                  });
                                  return;
                                }

                                setPopupState(() {
                                  popupError = null;
                                  isSaving = true;
                                });

                                try {
                                  final selectedEmployees = _selectedEmployeesFromIds(
                                    selectedEmployeeIds,
                                    availableEmployees,
                                  );

                                  await AppointmentService.addAppointment(
                                    title: eventNameController.text.trim(),
                                    date: _normalizeDate(dateController.text.trim()),
                                    startTime: _normalizeTimeInput(startTimeController.text.trim()),
                                    endTime: _normalizeEndTimeInput(
                                      start: startTimeController.text.trim(),
                                      end: endTimeController.text.trim(),
                                    ),
                                    clientId: selectedClient!.id,
                                    clientName: selectedClient!.name,
                                    clientPhone: _clientDisplayContactFromRecord(selectedClient!),
                                    employeeId: _joinStoredValues(
                                      selectedEmployees.map((employee) => employee.id),
                                    ),
                                    employeeName: _joinStoredValues(
                                      selectedEmployees.map((employee) => employee.name),
                                    ),
                                    address: addressController.text.trim(),
                                    notes: noteController.text.trim(),
                                    materialsNeeded: materialsController.text.trim(),
                                    pictures: picturesController.text.trim(),
                                  );

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                } catch (e) {
                                  setPopupState(() {
                                    isSaving = false;
                                    popupError = 'Error: $e';
                                  });
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
                                isSaving ? tr(context, 'Saving...') : tr(context, 'Create Event'),
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
    },
  );
}


/* ---------------- EDIT EVENT LIGHT ---------------- */



Future<void> showEditCalendarEventPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
    }) async {
  final eventNameController = TextEditingController(text: appointment.title);
  final dateController = TextEditingController(text: appointment.date);
  final startTimeController = TextEditingController(text: appointment.startTime);
  final endTimeController = TextEditingController(text: appointment.endTime);
  final clientController = TextEditingController(text: appointment.clientName);
  final addressController = TextEditingController(text: appointment.address);
  final noteController = TextEditingController(text: appointment.notes);
  final materialsController = TextEditingController(text: appointment.materialsNeeded);
  final picturesController = TextEditingController(text: appointment.pictures);

  final Set<String> selectedEmployeeIds = _splitStoredValues(appointment.employeeId).toSet();
  List<EmployeeRecord> availableEmployees = [];
  String selectedClientId = appointment.clientId;
  String selectedClientName = appointment.clientName;
  String selectedClientContact = appointment.clientPhone;
  List<ClientRecord> clientResults = [];
  List<dynamic> addressResults = [];
  bool isSearchingAddresses = false;
  bool isSaving = false;
  String? popupError;

  Future<void> searchClients(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        clientResults = [];
        selectedClientId = '';
        selectedClientName = '';
        selectedClientContact = '';
      });
      return;
    }

    final results = await ClientService.searchClients(query);

    setPopupState(() {
      clientResults = results;
    });
  }

  Future<void> searchAddresses(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
      return;
    }

    setPopupState(() {
      isSearchingAddresses = true;
    });

    try {
      final results = await GooglePlacesService.autocomplete(query);

      setPopupState(() {
        addressResults = List<dynamic>.from(results);
        isSearchingAddresses = false;
      });
    } catch (_) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
    }
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setPopupState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              final selectedClientSummary = _clientSummaryText(
                clientName: selectedClientName,
                clientContact: selectedClientContact,
              );

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
                              tr(context, 'Edit Event'),
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
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: dateController,
                            hintText: tr(context, 'Date'),
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextField(
                                  controller: startTimeController,
                                  hintText: tr(context, 'Start Time'),
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextField(
                                  controller: endTimeController,
                                  hintText: tr(context, 'End Time'),
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: clientController,
                            hintText: tr(context, 'Client * (search by name or phone number)'),
                            onChanged: (value) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                              searchClients(value, setPopupState);
                            },
                          ),
                          if (clientResults.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Container(
                              constraints: BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFFD8D8D8)),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: clientResults.length,
                                itemBuilder: (context, index) {
                                  final client = clientResults[index];
                                  return ListTile(
                                    title: Text(_clientDisplayNameFromRecord(client)),
                                    subtitle: Text(_clientDisplayContactFromRecord(client)),
                                    onTap: () {
                                      setPopupState(() {
                                        selectedClientId = client.id;
                                        selectedClientName = client.name;
                                        selectedClientContact = _clientDisplayContactFromRecord(client);
                                        clientController.text = _clientDisplayNameFromRecord(client);
                                        addressController.text = client.address.trim();
                                        clientResults = [];
                                        addressResults = [];
                                        popupError = null;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          if (selectedClientSummary.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Text(
                              selectedClientSummary,
                              style: TextStyle(fontSize: 13, color: Colors.black54),
                            ),
                          ],
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: addressController,
                            hintText: tr(context, 'Address *'),
                            suffixIcon: Icons.map_outlined,
                            onChanged: (value) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                              searchAddresses(value, setPopupState);
                            },
                          ),
                          if (isSearchingAddresses) ...[
                            SizedBox(height: 8),
                            Center(child: CircularProgressIndicator()),
                          ] else if (addressResults.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Container(
                              constraints: BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFFD8D8D8)),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: addressResults.length,
                                itemBuilder: (context, index) {
                                  final suggestion = addressResults[index];
                                  final suggestionText = _addressSuggestionText(suggestion);

                                  return ListTile(
                                    title: Text(suggestionText),
                                    onTap: () {
                                      setPopupState(() {
                                        addressController.text = suggestionText;
                                        addressResults = [];
                                        popupError = null;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: noteController,
                            hintText: tr(context, 'Type the note here...'),
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: materialsController,
                            hintText: tr(context, 'Type the materials here...'),
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: picturesController,
                            hintText: tr(context, 'Insert pictures here...'),
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          StreamBuilder<List<EmployeeRecord>>(
                            stream: UserService.employeesStream(),
                            builder: (context, snapshot) {
                              final employees = _normalizeEmployees(snapshot.data ?? []);

                              if (snapshot.connectionState == ConnectionState.waiting &&
                                  employees.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              availableEmployees = employees;

                              return _employeeSelectorLight(
                                context: context,
                                employees: employees,
                                selectedEmployeeIds: selectedEmployeeIds,
                                onSelected: (employeeId) {
                                  setPopupState(() {
                                    if (selectedEmployeeIds.contains(employeeId)) {
                                      selectedEmployeeIds.remove(employeeId);
                                    } else {
                                      selectedEmployeeIds.add(employeeId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                          SizedBox(height: 16),
                          if (popupError != null) ...[
                            _popupInlineErrorLight(popupError!),
                            SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(tr(context, 'Delete Event')),
                                          content: Text(tr(context, 'Are you sure you want to delete this event?')),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: Text(tr(context, 'Cancel')),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: Text(tr(context, 'Delete')),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        await AppointmentService.deleteAppointment(appointment.id);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.redAccent),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      tr(context, 'Delete'),
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                      if (selectedClientId.trim().isEmpty) {
                                        setPopupState(() {
                                          popupError = tr(context, 'Please select a client');
                                        });
                                        return;
                                      }

                                      if (addressController.text.trim().isEmpty) {
                                        setPopupState(() {
                                          popupError = tr(context, 'Address is required');
                                        });
                                        return;
                                      }

                                      setPopupState(() {
                                        popupError = null;
                                        isSaving = true;
                                      });

                                      try {
                                        final selectedEmployees = _selectedEmployeesFromIds(
                                          selectedEmployeeIds,
                                          availableEmployees,
                                        );

                                        await FirebaseFirestore.instance
                                            .collection('appointments')
                                            .doc(appointment.id)
                                            .update({
                                          'title': eventNameController.text.trim(),
                                          'date': _normalizeDate(dateController.text.trim()),
                                          'startTime': _normalizeTimeInput(startTimeController.text.trim()),
                                          'endTime': _normalizeEndTimeInput(
                                            start: startTimeController.text.trim(),
                                            end: endTimeController.text.trim(),
                                          ),
                                          'clientId': selectedClientId.trim(),
                                          'clientName': selectedClientName.trim(),
                                          'clientPhone': selectedClientContact.trim(),
                                          'employeeId': _joinStoredValues(
                                            selectedEmployees.map((employee) => employee.id),
                                          ),
                                          'employeeName': _joinStoredValues(
                                            selectedEmployees.map((employee) => employee.name),
                                          ),
                                          'address': addressController.text.trim(),
                                          'notes': noteController.text.trim(),
                                          'materialsNeeded': materialsController.text.trim(),
                                          'pictures': picturesController.text.trim(),
                                          'updatedAt': FieldValue.serverTimestamp(),
                                        });

                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        setPopupState(() {
                                          isSaving = false;
                                          popupError = 'Error: $e';
                                        });
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
                                      isSaving ? tr(context, 'Saving...') : tr(context, 'Update Event'),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
    },
  );
}

/* ---------------- EDIT EVENT DARK ---------------- */

Future<void> showEditCalendarEventDarkPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
    }) async {
  final eventNameController = TextEditingController(text: appointment.title);
  final dateController = TextEditingController(text: appointment.date);
  final startTimeController = TextEditingController(text: appointment.startTime);
  final endTimeController = TextEditingController(text: appointment.endTime);
  final clientController = TextEditingController(text: appointment.clientName);
  final addressController = TextEditingController(text: appointment.address);
  final noteController = TextEditingController(text: appointment.notes);
  final materialsController = TextEditingController(text: appointment.materialsNeeded);
  final picturesController = TextEditingController(text: appointment.pictures);

  final Set<String> selectedEmployeeIds = _splitStoredValues(appointment.employeeId).toSet();
  List<EmployeeRecord> availableEmployees = [];
  String selectedClientId = appointment.clientId;
  String selectedClientName = appointment.clientName;
  String selectedClientContact = appointment.clientPhone;
  List<ClientRecord> clientResults = [];
  List<dynamic> addressResults = [];
  bool isSearchingAddresses = false;
  bool isSaving = false;
  String? popupError;

  Future<void> searchClients(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        clientResults = [];
        selectedClientId = '';
        selectedClientName = '';
        selectedClientContact = '';
      });
      return;
    }

    final results = await ClientService.searchClients(query);

    setPopupState(() {
      clientResults = results;
    });
  }

  Future<void> searchAddresses(
      String query,
      void Function(void Function()) setPopupState,
      ) async {
    if (query.trim().isEmpty) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
      return;
    }

    setPopupState(() {
      isSearchingAddresses = true;
    });

    try {
      final results = await GooglePlacesService.autocomplete(query);

      setPopupState(() {
        addressResults = List<dynamic>.from(results);
        isSearchingAddresses = false;
      });
    } catch (_) {
      setPopupState(() {
        addressResults = [];
        isSearchingAddresses = false;
      });
    }
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setPopupState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              final selectedClientSummary = _clientSummaryText(
                clientName: selectedClientName,
                clientContact: selectedClientContact,
              );

              return Container(
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
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
                                color: Color(0xFF3A3A3A),
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
                          Center(
                            child: Text(
                              tr(context, 'Edit Event'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(height: 18),
                          _popupTextFieldDark(
                            controller: eventNameController,
                            hintText: tr(context, 'Event name'),
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: dateController,
                            hintText: tr(context, 'Date'),
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: startTimeController,
                                  hintText: tr(context, 'Start Time'),
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: endTimeController,
                                  hintText: tr(context, 'End Time'),
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: clientController,
                            hintText: tr(context, 'Client * (search by name or phone number)'),
                            onChanged: (value) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                              searchClients(value, setPopupState);
                            },
                          ),
                          if (clientResults.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Container(
                              constraints: BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Color(0xFF171717),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFF2D2D2D)),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: clientResults.length,
                                itemBuilder: (context, index) {
                                  final client = clientResults[index];
                                  return ListTile(
                                    title: Text(
                                      _clientDisplayNameFromRecord(client),
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    subtitle: Text(
                                      _clientDisplayContactFromRecord(client),
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    onTap: () {
                                      setPopupState(() {
                                        selectedClientId = client.id;
                                        selectedClientName = client.name;
                                        selectedClientContact = _clientDisplayContactFromRecord(client);
                                        clientController.text = _clientDisplayNameFromRecord(client);
                                        addressController.text = client.address.trim();
                                        clientResults = [];
                                        addressResults = [];
                                        popupError = null;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          if (selectedClientSummary.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Text(
                              selectedClientSummary,
                              style: TextStyle(fontSize: 13, color: Colors.white70),
                            ),
                          ],
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: addressController,
                            hintText: tr(context, 'Address *'),
                            suffixIcon: Icons.map_outlined,
                            onChanged: (value) {
                              if (popupError != null) {
                                setPopupState(() {
                                  popupError = null;
                                });
                              }
                              searchAddresses(value, setPopupState);
                            },
                          ),
                          if (isSearchingAddresses) ...[
                            SizedBox(height: 8),
                            Center(child: CircularProgressIndicator()),
                          ] else if (addressResults.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Container(
                              constraints: BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Color(0xFF171717),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFF2D2D2D)),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: addressResults.length,
                                itemBuilder: (context, index) {
                                  final suggestion = addressResults[index];
                                  final suggestionText = _addressSuggestionText(suggestion);

                                  return ListTile(
                                    title: Text(
                                      suggestionText,
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    onTap: () {
                                      setPopupState(() {
                                        addressController.text = suggestionText;
                                        addressResults = [];
                                        popupError = null;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: noteController,
                            hintText: tr(context, 'Type the note here...'),
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: materialsController,
                            hintText: tr(context, 'Type the materials here...'),
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: picturesController,
                            hintText: tr(context, 'Insert pictures here...'),
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          StreamBuilder<List<EmployeeRecord>>(
                            stream: UserService.employeesStream(),
                            builder: (context, snapshot) {
                              final employees = _normalizeEmployees(snapshot.data ?? []);

                              if (snapshot.connectionState == ConnectionState.waiting &&
                                  employees.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              availableEmployees = employees;

                              return _employeeSelectorDark(
                                context: context,
                                employees: employees,
                                selectedEmployeeIds: selectedEmployeeIds,
                                onSelected: (employeeId) {
                                  setPopupState(() {
                                    if (selectedEmployeeIds.contains(employeeId)) {
                                      selectedEmployeeIds.remove(employeeId);
                                    } else {
                                      selectedEmployeeIds.add(employeeId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                          SizedBox(height: 16),
                          if (popupError != null) ...[
                            _popupInlineErrorDark(popupError!),
                            SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(tr(context, 'Delete Event')),
                                          content: Text(tr(context, 'Are you sure you want to delete this event?')),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: Text(tr(context, 'Cancel')),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: Text(tr(context, 'Delete')),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        await AppointmentService.deleteAppointment(appointment.id);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.redAccent),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      tr(context, 'Delete'),
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                      if (selectedClientId.trim().isEmpty) {
                                        setPopupState(() {
                                          popupError = tr(context, 'Please select a client');
                                        });
                                        return;
                                      }

                                      if (addressController.text.trim().isEmpty) {
                                        setPopupState(() {
                                          popupError = tr(context, 'Address is required');
                                        });
                                        return;
                                      }

                                      setPopupState(() {
                                        popupError = null;
                                        isSaving = true;
                                      });

                                      try {
                                        final selectedEmployees = _selectedEmployeesFromIds(
                                          selectedEmployeeIds,
                                          availableEmployees,
                                        );

                                        await FirebaseFirestore.instance
                                            .collection('appointments')
                                            .doc(appointment.id)
                                            .update({
                                          'title': eventNameController.text.trim(),
                                          'date': _normalizeDate(dateController.text.trim()),
                                          'startTime': _normalizeTimeInput(startTimeController.text.trim()),
                                          'endTime': _normalizeEndTimeInput(
                                            start: startTimeController.text.trim(),
                                            end: endTimeController.text.trim(),
                                          ),
                                          'clientId': selectedClientId.trim(),
                                          'clientName': selectedClientName.trim(),
                                          'clientPhone': selectedClientContact.trim(),
                                          'employeeId': _joinStoredValues(
                                            selectedEmployees.map((employee) => employee.id),
                                          ),
                                          'employeeName': _joinStoredValues(
                                            selectedEmployees.map((employee) => employee.name),
                                          ),
                                          'address': addressController.text.trim(),
                                          'notes': noteController.text.trim(),
                                          'materialsNeeded': materialsController.text.trim(),
                                          'pictures': picturesController.text.trim(),
                                          'updatedAt': FieldValue.serverTimestamp(),
                                        });

                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        setPopupState(() {
                                          isSaving = false;
                                          popupError = 'Error: $e';
                                        });
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
                                      isSaving ? tr(context, 'Saving...') : tr(context, 'Update Event'),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
    },
  );
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


String _clientSummaryText({
  required String clientName,
  required String clientContact,
}) {
  final name = clientName.trim();
  final contact = clientContact.trim();

  if (name.isEmpty && contact.isEmpty) return '';
  if (name.isEmpty) return contact;
  if (contact.isEmpty) return name;
  return '$name ($contact)';
}

String _joinStoredValues(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(', ');
}

List<EmployeeRecord> _selectedEmployeesFromIds(
    Set<String> selectedIds,
    List<EmployeeRecord> employees,
    ) {
  final selected = employees.where((employee) => selectedIds.contains(employee.id)).toList();
  selected.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return selected;
}


String _normalizeTimeInput(String value) {
  final raw = value.trim().toLowerCase();
  if (raw.isEmpty) return '';

  final regex = RegExp(r'^(\d{1,2})(?:[:.](\d{1,2}))?\s*([ap]m)?$');
  final match = regex.firstMatch(raw);
  if (match == null) return value.trim();

  final hourText = match.group(1)!;
  final minuteText = match.group(2);
  final meridiem = match.group(3);

  var hour = int.tryParse(hourText);
  var minute = int.tryParse(minuteText ?? '0');

  if (hour == null || minute == null) return value.trim();
  if (minute < 0 || minute > 59) return value.trim();

  if (meridiem != null) {
    if (hour < 1 || hour > 12) return value.trim();
    return '$hour:${minute.toString().padLeft(2, '0')} $meridiem';
  }

  if (hour < 0 || hour > 23) return value.trim();
  return '$hour:${minute.toString().padLeft(2, '0')}';
}

String _normalizeEndTimeInput({
  required String start,
  required String end,
}) {
  final normalizedEnd = _normalizeTimeInput(end);
  if (normalizedEnd.isNotEmpty) return normalizedEnd;

  final normalizedStart = _normalizeTimeInput(start);
  if (normalizedStart.isEmpty) return '';

  return _addOneHourToTime(normalizedStart);
}

String _addOneHourToTime(String value) {
  final normalized = _normalizeTimeInput(value);
  final time = _parseTimeOfDay(normalized);
  if (time == null) return normalized;

  final totalMinutes = (time.hour * 60) + time.minute + 60;
  final wrappedMinutes = totalMinutes % (24 * 60);
  final newHour = wrappedMinutes ~/ 60;
  final newMinute = wrappedMinutes % 60;
  final usesMeridiem = RegExp(r'\b[ap]m\b', caseSensitive: false).hasMatch(normalized);

  if (usesMeridiem) {
    final suffix = newHour >= 12 ? 'pm' : 'am';
    var displayHour = newHour % 12;
    if (displayHour == 0) displayHour = 12;
    return '$displayHour:${newMinute.toString().padLeft(2, '0')} $suffix';
  }

  return '$newHour:${newMinute.toString().padLeft(2, '0')}';
}

DateTime? _appointmentStartDateTime(AppointmentRecord appointment) {
  try {
    final dateParts = appointment.date.trim().split('-');
    if (dateParts.length != 3) return null;

    final year = int.parse(dateParts[0]);
    final month = int.parse(dateParts[1]);
    final day = int.parse(dateParts[2]);

    final time = _parseTimeOfDay(appointment.startTime);
    if (time == null) return null;

    return DateTime(year, month, day, time.hour, time.minute);
  } catch (_) {
    return null;
  }
}

TimeOfDay? _parseTimeOfDay(String value) {
  final raw = _normalizeTimeInput(value).trim().toLowerCase();
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

Widget _detailSectionLabel({
  required String label,
  required Color color,
}) {
  return Padding(
    padding: EdgeInsets.only(left: 2, bottom: 6),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

Widget _detailDisplayBlockLight({
  required BuildContext context,
  required String label,
  required String value,
  IconData? suffixIcon,
  Widget? prefix,
  int maxLines = 1,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _detailSectionLabel(label: label, color: Color(0xFF5F5F5F)),
      _detailDisplayFieldLight(
        context: context,
        label: label,
        value: value,
        suffixIcon: suffixIcon,
        prefix: prefix,
        maxLines: maxLines,
      ),
    ],
  );
}

Widget _detailDisplayBlockDark({
  required BuildContext context,
  required String label,
  required String value,
  IconData? suffixIcon,
  Widget? prefix,
  int maxLines = 1,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _detailSectionLabel(label: label, color: Color(0xFFB0B0B0)),
      _detailDisplayFieldDark(
        context: context,
        label: label,
        value: value,
        suffixIcon: suffixIcon,
        prefix: prefix,
        maxLines: maxLines,
      ),
    ],
  );
}

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

Future<void> showCalendarEventDetailsPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
      required Color employeeColor,
      required List<EmployeeRecord> employees,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.90,
        minChildSize: 0.65,
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
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
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
                        tr(context, 'Event Details'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          children: [
                            _detailDisplayBlockLight(
                              context: context,
                              label: tr(context, 'Job Title'),
                              value: appointment.title,
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockLight(
                              context: context,
                              label: tr(context, 'Date'),
                              value: appointment.date,
                              suffixIcon: Icons.calendar_today_outlined,
                            ),
                            SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _detailDisplayBlockLight(
                                    context: context,
                                    label: tr(context, 'Start Time'),
                                    value: appointment.startTime,
                                    suffixIcon: Icons.access_time_outlined,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: _detailDisplayBlockLight(
                                    context: context,
                                    label: tr(context, 'End Time'),
                                    value: appointment.endTime,
                                    suffixIcon: Icons.access_time_outlined,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 14),
                            GestureDetector(
                              onTap: () async {
                                await _openClientDetailsFromAppointment(
                                  context,
                                  appointment: appointment,
                                  isDark: false,
                                );
                              },
                              child: _detailDisplayBlockLight(
                                context: context,
                                label: tr(context, 'Client name (phone number)'),
                                value: _clientDisplay(appointment),
                              ),
                            ),
                            SizedBox(height: 14),
                            GestureDetector(
                              onTap: () {
                                final address = appointment.address.trim();
                                if (address.isNotEmpty) {
                                  openMapsOptions(context, address);
                                }
                              },
                              child: _detailDisplayBlockLight(
                                context: context,
                                label: tr(context, 'Address'),
                                value: appointment.address,
                                suffixIcon: Icons.map,
                              ),
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockLight(
                              context: context,
                              label: tr(context, 'Selected Employee'),
                              value: appointment.employeeName,
                              prefix: _employeeBadgesForNames(
                                appointment.employeeName,
                                employees: employees,
                                isDark: false,
                              ),
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockLight(
                              context: context,
                              label: tr(context, 'Notes'),
                              value: appointment.notes,
                              suffixIcon: Icons.note_alt_outlined,
                              maxLines: 3,
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockLight(
                              context: context,
                              label: tr(context, 'Materials needed'),
                              value: appointment.materialsNeeded,
                              suffixIcon: Icons.build_outlined,
                              maxLines: 3,
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockLight(
                              context: context,
                              label: tr(context, 'Pictures'),
                              value: appointment.pictures,
                              suffixIcon: Icons.image_outlined,
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (_hasAppointmentStarted(appointment)) {
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
                          tr(context, _hasAppointmentStarted(appointment) ? 'Event Done' : 'Close'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

Future<void> showCalendarEventDetailsDarkPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
      required Color employeeColor,
      required List<EmployeeRecord> employees,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.90,
        minChildSize: 0.65,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Color(0xFF121212),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
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
                        tr(context, 'Event Details'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          children: [
                            _detailDisplayBlockDark(
                              context: context,
                              label: tr(context, 'Job Title'),
                              value: appointment.title,
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockDark(
                              context: context,
                              label: tr(context, 'Date'),
                              value: appointment.date,
                              suffixIcon: Icons.calendar_today_outlined,
                            ),
                            SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _detailDisplayBlockDark(
                                    context: context,
                                    label: tr(context, 'Start Time'),
                                    value: appointment.startTime,
                                    suffixIcon: Icons.access_time_outlined,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: _detailDisplayBlockDark(
                                    context: context,
                                    label: tr(context, 'End Time'),
                                    value: appointment.endTime,
                                    suffixIcon: Icons.access_time_outlined,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 14),
                            GestureDetector(
                              onTap: () async {
                                await _openClientDetailsFromAppointment(
                                  context,
                                  appointment: appointment,
                                  isDark: true,
                                );
                              },
                              child: _detailDisplayBlockDark(
                                context: context,
                                label: tr(context, 'Client name (phone number)'),
                                value: _clientDisplay(appointment),
                              ),
                            ),
                            SizedBox(height: 14),
                            GestureDetector(
                              onTap: () {
                                final address = appointment.address.trim();
                                if (address.isNotEmpty) {
                                  openMapsOptions(context, address);
                                }
                              },
                              child: _detailDisplayBlockDark(
                                context: context,
                                label: tr(context, 'Address'),
                                value: appointment.address,
                                suffixIcon: Icons.map,
                              ),
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockDark(
                              context: context,
                              label: tr(context, 'Selected Employee'),
                              value: appointment.employeeName,
                              prefix: _employeeBadgesForNames(
                                appointment.employeeName,
                                employees: employees,
                                isDark: true,
                              ),
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockDark(
                              context: context,
                              label: tr(context, 'Notes'),
                              value: appointment.notes,
                              suffixIcon: Icons.note_alt_outlined,
                              maxLines: 3,
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockDark(
                              context: context,
                              label: tr(context, 'Materials needed'),
                              value: appointment.materialsNeeded,
                              suffixIcon: Icons.build_outlined,
                              maxLines: 3,
                            ),
                            SizedBox(height: 14),
                            _detailDisplayBlockDark(
                              context: context,
                              label: tr(context, 'Pictures'),
                              value: appointment.pictures,
                              suffixIcon: Icons.image_outlined,
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (_hasAppointmentStarted(appointment)) {
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
                          tr(context, _hasAppointmentStarted(appointment) ? 'Event Done' : 'Close'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

String _appointmentClientLine(AppointmentRecord appointment) {
  final name = appointment.clientName.trim();
  final contact = appointment.clientPhone.trim();

  if (name.isEmpty && contact.isEmpty) {
    return '';
  }
  if (name.isEmpty) {
    return contact;
  }
  if (contact.isEmpty) {
    return name;
  }
  return '$name ($contact)';
}

String _detailValue(BuildContext context, String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? tr(context, 'Not provided') : trimmed;
}

String _clientDisplay(AppointmentRecord appointment) {
  final name = appointment.clientName.trim();
  final phone = appointment.clientPhone.trim();

  if (name.isEmpty && phone.isEmpty) {
    return '';
  }
  if (name.isEmpty) {
    return phone;
  }
  if (phone.isEmpty) {
    return name;
  }
  return '$name ($phone)';
}

Future<ClientRecord?> _loadClientForAppointment(AppointmentRecord appointment) async {
  final clientId = appointment.clientId.trim();

  if (clientId.isNotEmpty) {
    final doc = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .get();

    if (doc.exists) {
      return ClientRecord.fromDoc(doc);
    }
  }

  final clientName = appointment.clientName.trim().toLowerCase();
  if (clientName.isEmpty) return null;

  final snapshot = await FirebaseFirestore.instance
      .collection('clients')
      .limit(50)
      .get();

  for (final doc in snapshot.docs) {
    final client = ClientRecord.fromDoc(doc);
    final businessName = client.businessName.trim().toLowerCase();
    final name = client.name.trim().toLowerCase();

    if (businessName == clientName || name == clientName) {
      return client;
    }
  }

  return null;
}

Future<void> _openClientDetailsFromAppointment(
    BuildContext context, {
      required AppointmentRecord appointment,
      required bool isDark,
    }) async {
  final client = await _loadClientForAppointment(appointment);
  if (client == null || !context.mounted) return;

  if (isDark) {
    await showClientDetailsDarkPopup(context, client: client);
  } else {
    await showClientDetailsPopup(context, client: client);
  }
}

Widget _detailDisplayFieldLight({
  required BuildContext context,
  required String label,
  required String value,
  IconData? suffixIcon,
  Widget? prefix,
  int maxLines = 1,
}) {
  return _detailDisplayFieldBase(
    context: context,
    label: label,
    value: value,
    suffixIcon: suffixIcon,
    prefix: prefix,
    maxLines: maxLines,
    fillColor: Colors.white,
    borderColor: Color(0xFFD8D8D8),
    textColor: Colors.black87,
    hintColor: Color(0xFF7A7A7A),
    iconColor: Color(0xFF7A7A7A),
  );
}

Widget _detailDisplayFieldDark({
  required BuildContext context,
  required String label,
  required String value,
  IconData? suffixIcon,
  Widget? prefix,
  int maxLines = 1,
}) {
  return _detailDisplayFieldBase(
    context: context,
    label: label,
    value: value,
    suffixIcon: suffixIcon,
    prefix: prefix,
    maxLines: maxLines,
    fillColor: Color(0xFF171717),
    borderColor: Color(0xFF2D2D2D),
    textColor: Colors.white,
    hintColor: Colors.white38,
    iconColor: Colors.white54,
  );
}

Widget _detailDisplayFieldBase({
  required BuildContext context,
  required String label,
  required String value,
  required Color fillColor,
  required Color borderColor,
  required Color textColor,
  required Color hintColor,
  required Color iconColor,
  IconData? suffixIcon,
  Widget? prefix,
  int maxLines = 1,
}) {
  final displayValue = _detailValue(context, value);

  return Container(
    width: double.infinity,
    constraints: BoxConstraints(minHeight: maxLines > 1 ? 76 : 54),
    padding: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: maxLines > 1 ? 14 : 12,
    ),
    decoration: BoxDecoration(
      color: fillColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
    ),
    child: Row(
      crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (prefix != null) ...[
          prefix,
          SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            displayValue,
            style: TextStyle(
              color: displayValue == tr(context, 'Not provided') ? hintColor : textColor,
              fontSize: 15,
              height: 1.35,
            ),
            maxLines: maxLines > 1 ? null : 1,
            overflow: maxLines > 1 ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
        if (suffixIcon != null) ...[
          SizedBox(width: 10),
          Icon(suffixIcon, color: iconColor, size: 20),
        ],
      ],
    ),
  );
}

Widget _employeeBadgeLight(String name, Color employeeColor) {
  return Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: employeeColor,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      _employeeInitials(name),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
  );
}

Widget _employeeBadgeDark(String name, Color employeeColor) {
  return Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: employeeColor,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      _employeeInitials(name),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}

Widget _employeeBadgesForNames(
    String rawNames, {
      required List<EmployeeRecord> employees,
      required bool isDark,
    }) {
  final employeeNames = _appointmentEmployeeNamesFromRaw(rawNames);
  if (employeeNames.isEmpty) {
    return SizedBox.shrink();
  }

  final visibleNames = employeeNames.take(3).toList();
  final extraCount = employeeNames.length - visibleNames.length;

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < visibleNames.length; i++) ...[
        if (i > 0) SizedBox(width: 4),
        _employeeBadgeForName(
          visibleNames[i],
          employees: employees,
          isDark: isDark,
        ),
      ],
      if (extraCount > 0) ...[
        SizedBox(width: 4),
        _extraEmployeesBadge(extraCount, isDark: isDark),
      ],
    ],
  );
}

Widget _employeeBadgeForName(
    String name, {
      required List<EmployeeRecord> employees,
      required bool isDark,
    }) {
  final employee = _employeeByName(name, employees);
  final color = employee?.color.withValues(alpha: isDark ? 0.95 : 1.0)
      ?? (isDark ? kPurple : Color(0xFFE7DDF9));

  return Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      _employeeInitials(name),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black87,
      ),
    ),
  );
}

Widget _extraEmployeesBadge(int count, {required bool isDark}) {
  return Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: isDark ? Color(0xFF3A3A3A) : Color(0xFFE2DED6),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      '+$count',
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : Colors.black87,
      ),
    ),
  );
}

List<String> _appointmentEmployeeNamesFromRaw(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return [];

  final normalized = trimmed
      .replaceAll('•', ',')
      .replaceAll('|', ',')
      .replaceAll('/', ',')
      .replaceAll(' + ', ',')
      .replaceAll(' & ', ',');

  return normalized
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();
}

EmployeeRecord? _employeeByName(String name, List<EmployeeRecord> employees) {
  final normalizedName = name.trim().toLowerCase();
  if (normalizedName.isEmpty) return null;

  for (final employee in employees) {
    if (employee.name.trim().toLowerCase() == normalizedName) {
      return employee;
    }
  }

  return null;
}


Color _appointmentCardColor(
    AppointmentRecord appointment, {
      required Color employeeColor,
      required bool isDark,
    }) {
  final employeeNames = _appointmentEmployeeNames(appointment);

  if (employeeNames.length <= 1) {
    return employeeColor;
  }

  return isDark ? Color(0xFF2A2A2A) : Color(0xFFF1E8D8);
}

List<String> _appointmentEmployeeNames(AppointmentRecord appointment) {
  return _appointmentEmployeeNamesFromRaw(appointment.employeeName);
}

Widget _appointmentAssignedEmployeesRow({
  required String employeeName,
  required List<EmployeeRecord> employees,
  required bool isDark,
}) {
  final employeeNames = _appointmentEmployeeNamesFromRaw(employeeName);
  final isMultiEmployee = employeeNames.length > 1;
  final labelColor = isDark ? Color(0xFFEDEDED) : Colors.black87;
  final mutedColor = isDark ? Color(0xFFD0D0D0) : Colors.black54;

  return Row(
    children: [
      Text(
        isMultiEmployee ? 'Team' : 'Employee',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: mutedColor,
        ),
      ),
      SizedBox(width: 8),
      _employeeBadgesForNames(
        employeeName,
        employees: employees,
        isDark: isDark,
      ),
      SizedBox(width: 8),
      Expanded(
        child: Text(
          employeeName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/* ---------------- EMPLOYEES ---------------- */

List<EmployeeRecord> _normalizeEmployees(List<EmployeeRecord> employees) {
  final list = [...employees];
  list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

String _employeeInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }

  return (parts[0][0] + parts[1][0]).toUpperCase();
}

Color _employeeBubbleColor(EmployeeRecord employee, bool isDark) {
  return employee.color.withValues(alpha: isDark ? 0.95 : 1.0);
}


EmployeeRecord? _employeeForAppointment(
    AppointmentRecord appointment,
    List<EmployeeRecord> employees,
    ) {
  final employeeIds = _splitStoredValues(appointment.employeeId);
  final employeeNames = _appointmentEmployeeNames(appointment)
      .map((name) => name.toLowerCase())
      .toList();

  for (final employee in employees) {
    if (employeeIds.isNotEmpty && employeeIds.contains(employee.id)) {
      return employee;
    }

    if (employeeNames.isNotEmpty &&
        employeeNames.contains(employee.name.trim().toLowerCase())) {
      return employee;
    }
  }

  return null;
}

String _appointmentEmployeeName(AppointmentRecord appointment) {
  return appointment.employeeName.trim();
}

Color _appointmentEmployeeColor(
    AppointmentRecord appointment, {
      required List<EmployeeRecord> employees,
      required bool isDark,
    }) {
  final employee = _employeeForAppointment(appointment, employees);
  final fallback = isDark ? kPurple : Color(0xFFE7DDF9);

  return employee?.color.withValues(alpha: isDark ? 0.90 : 0.28) ?? fallback;
}

Widget _calendarEventDots(
    List<AppointmentRecord> appointments, {
      required List<EmployeeRecord> employees,
      required bool isDark,
    }) {
  final colors = <Color>[];

  for (final appointment in appointments) {
    final employeeIds = _splitStoredValues(appointment.employeeId);
    final employeeNames = _appointmentEmployeeNames(appointment);
    final assignedCount = employeeIds.isNotEmpty ? employeeIds.length : employeeNames.length;

    if (assignedCount > 1) {
      final teamColor = isDark ? Colors.white : Colors.black;
      if (!colors.any((existing) => existing.toARGB32() == teamColor.toARGB32())) {
        colors.add(teamColor);
      }
      continue;
    }

    if (employeeIds.isNotEmpty) {
      final employeeId = employeeIds.first;
      final employee = employees.where((e) => e.id == employeeId).cast<EmployeeRecord?>().firstWhere(
            (e) => e != null,
        orElse: () => null,
      );
      final color = employee != null
          ? _employeeBubbleColor(employee, isDark)
          : null;

      if (color != null &&
          !colors.any((existing) => existing.toARGB32() == color.toARGB32())) {
        colors.add(color);
      }
      continue;
    }

    if (employeeNames.isNotEmpty) {
      final employee = _employeeByName(employeeNames.first, employees);
      final color = employee != null
          ? _employeeBubbleColor(employee, isDark)
          : (isDark ? kPurple : Color(0xFFE7DDF9));

      if (!colors.any((existing) => existing.toARGB32() == color.toARGB32())) {
        colors.add(color);
      }
      continue;
    }

    final fallback = isDark ? kPurple : Color(0xFFE7DDF9);
    if (!colors.any((existing) => existing.toARGB32() == fallback.toARGB32())) {
      colors.add(fallback);
    }
  }

  final visibleColors = colors.take(3).toList();

  return SizedBox(
    height: 5,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibleColors.length; i++) ...[
          if (i > 0) SizedBox(width: 3),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: visibleColors[i],
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _employeeSelectorLight({
  required BuildContext context,
  required List<EmployeeRecord> employees,
  required Set<String> selectedEmployeeIds,
  required ValueChanged<String> onSelected,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Color(0xFFD8D8D8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'Select Employees'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        SizedBox(height: 12),
        if (employees.isEmpty)
          Text(
            tr(context, 'No employees found'),
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF7A7A7A),
            ),
          )
        else
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: employees.map((employee) {
              final isSelected = selectedEmployeeIds.contains(employee.id);

              return GestureDetector(
                onTap: () => onSelected(employee.id),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _employeeBubbleColor(employee, false),
                            border: Border.all(
                              color: isSelected ? Colors.black87 : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _employeeInitials(employee.name),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.check,
                                size: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    ),
  );
}

Widget _employeeSelectorDark({
  required BuildContext context,
  required List<EmployeeRecord> employees,
  required Set<String> selectedEmployeeIds,
  required ValueChanged<String> onSelected,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(
      color: Color(0xFF171717),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Color(0xFF2D2D2D)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'Select Employees'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 12),
        if (employees.isEmpty)
          Text(
            tr(context, 'No employees found'),
            style: TextStyle(
              fontSize: 13,
              color: Colors.white54,
            ),
          )
        else
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: employees.map((employee) {
              final isSelected = selectedEmployeeIds.contains(employee.id);

              return GestureDetector(
                onTap: () => onSelected(employee.id),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _employeeBubbleColor(employee, true),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _employeeInitials(employee.name),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.check,
                                size: 11,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    ),
  );
}

Widget _popupTextField({
  required TextEditingController controller,
  required String hintText,
  IconData? suffixIcon,
  int maxLines = 1,
  bool enabled = true,
  ValueChanged<String>? onChanged,
}) {
  final isMultiline = maxLines > 1;

  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      onChanged: onChanged,
      style: TextStyle(color: Colors.black87),
      textAlignVertical:
      isMultiline ? TextAlignVertical.top : TextAlignVertical.center,
      decoration: InputDecoration(
        labelText: hintText, // 👈 key change
        floatingLabelBehavior: FloatingLabelBehavior.auto,

        labelStyle: TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 14,
        ),

        floatingLabelStyle: TextStyle(
          color: kPurple,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),

        suffixIcon: suffixIcon != null
            ? Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(suffixIcon, color: Color(0xFF8E8E93)),
        )
            : null,

        filled: true,
        fillColor: Colors.white,

        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isMultiline ? 16 : 14,
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Color(0xFFE5E5EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: kPurple, width: 2),
        ),
      ),
    ),
  );
}

Widget _popupTextFieldDark({
  required TextEditingController controller,
  required String hintText,
  IconData? suffixIcon,
  int maxLines = 1,
  bool enabled = true,
  ValueChanged<String>? onChanged,
}) {
  final isMultiline = maxLines > 1;

  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      onChanged: onChanged,
      style: TextStyle(
        color: Colors.white,
        fontSize: 15,
      ),
      textAlignVertical:
      isMultiline ? TextAlignVertical.top : TextAlignVertical.center,
      decoration: InputDecoration(
        labelText: hintText,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: Colors.white38,
          fontSize: 14,
        ),
        floatingLabelStyle: TextStyle(
          color: kPurple,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        suffixIcon: suffixIcon != null
            ? Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(
            suffixIcon,
            color: Colors.white54,
            size: 20,
          ),
        )
            : null,
        suffixIconConstraints: BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        filled: true,
        fillColor: Color(0xFF171717),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isMultiline ? 16 : 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFF2D2D2D),
            width: 1.2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFF2D2D2D),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: kPurple,
            width: 2,
          ),
        ),
      ),
    ),
  );
}
bool _sameDateString(String a, String b) {
  return a.trim() == b.trim();
}

String _formatDateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _normalizeDate(String value) {
  final trimmed = value.trim();

  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
    return trimmed;
  }

  final parts = trimmed.split('/');
  if (parts.length == 3) {
    final day = parts[0].padLeft(2, '0');
    final month = parts[1].padLeft(2, '0');
    final year = parts[2];
    return '$year-$month-$day';
  }

  return trimmed;
}

Widget _popupInlineErrorLight(String message) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Color(0xFFFFE5E5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Color(0xFFFFB3B3)),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: Colors.red,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Widget _popupInlineErrorDark(String message) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Color(0xFF2A1212),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.redAccent),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: Colors.redAccent,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
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