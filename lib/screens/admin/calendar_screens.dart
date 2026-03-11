import 'package:flutter/material.dart';

import '../../models/appointment_record.dart';
import '../../models/client_record.dart';
import '../../models/employee_record.dart';
import '../../utils/colors.dart';
import '../../widgets/admin_drawers.dart';

class AdminCalendarPage extends StatefulWidget {
  const AdminCalendarPage({super.key});

  @override
  State<AdminCalendarPage> createState() => _AdminCalendarPageState();
}

class _AdminCalendarPageState extends State<AdminCalendarPage> {
  DateTime displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();

  final Map<String, List<Map<String, dynamic>>> events = {};

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
    final firstVisibleDay = firstDayOfMonth.subtract(
      Duration(days: startOffset),
    );

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
    final selectedEvents = events[dateKey(selectedDate)] ?? [];
    final today = DateTime.now();

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
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () {
                        Scaffold.of(context).openEndDrawer();
                      },
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
                        monthName(displayedMonth.month),
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
                  Expanded(child: Center(child: Text('Sun', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Mon', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Tue', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Wed', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Thu', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Fri', style: TextStyle(color: Colors.black54, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Sat', style: TextStyle(color: Colors.black54, fontSize: 16)))),
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
                        'No events for ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap the + button to add one later.',
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
                  separatorBuilder: (_, __) => SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];
                    return Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Color(0xFFE7DDF9),
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
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () async {
                                  await showEditCalendarEventPopup(
                                    context,
                                    event: event,
                                  );
                                  if (context.mounted) {
                                    setState(() {});
                                  }
                                },
                                child: Padding(
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
                          SizedBox(height: 8),
                          Text(
                            event['title'] ?? '',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if ((event['subtitle'] ?? '').toString().isNotEmpty) ...[
                            SizedBox(height: 6),
                            Text(
                              event['subtitle'],
                              style: TextStyle(
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

  final Map<String, List<Map<String, dynamic>>> events = {};

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
    final firstVisibleDay = firstDayOfMonth.subtract(
      Duration(days: startOffset),
    );

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
    Color background = Colors.black;
    Color primaryText = Colors.white;
    Color secondaryText = Color(0xFF9E9E9E);
    Color fadedText = Color(0xFF5F5F5F);
    Color dividerColor = Color(0xFF3A3A3A);
    Color cardColor = kPurple;

    final calendarDays = buildCalendarDays(displayedMonth);
    final selectedEvents = events[dateKey(selectedDate)] ?? [];
    final today = DateTime.now();

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
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: primaryText,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () {
                        Scaffold.of(context).openEndDrawer();
                      },
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
                        monthName(displayedMonth.month),
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
                  Expanded(child: Center(child: Text('Sun', style: TextStyle(color: secondaryText, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Mon', style: TextStyle(color: secondaryText, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Tue', style: TextStyle(color: secondaryText, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Wed', style: TextStyle(color: secondaryText, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Thu', style: TextStyle(color: secondaryText, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Fri', style: TextStyle(color: secondaryText, fontSize: 16)))),
                  Expanded(child: Center(child: Text('Sat', style: TextStyle(color: secondaryText, fontSize: 16)))),
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
                                  ? Colors.white
                                  : fadedText,
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
              SizedBox(height: 18),
              Expanded(
                child: selectedEvents.isEmpty
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
                        'No events for ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        style: TextStyle(
                          fontSize: 16,
                          color: secondaryText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap the + button to add one later.',
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
                  separatorBuilder: (_, __) => SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];
                    return Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
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
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFFD8CFFF),
                                  ),
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () async {
                                  await showEditCalendarEventDarkPopup(
                                    context,
                                    event: event,
                                  );
                                  if (context.mounted) {
                                    setState(() {});
                                  }
                                },
                                child: Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.more_horiz,
                                    color: Color(0xFFE7DFFF),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            event['title'] ?? '',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          if ((event['subtitle'] ?? '').toString().isNotEmpty) ...[
                            SizedBox(height: 6),
                            Text(
                              event['subtitle'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFFE7DFFF),
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

/* ---------------- RIGHT MENU LIGHT ---------------- */


Future<void> showAddEventPopup(
    BuildContext context,
    DateTime selectedDate,
    ) async {
  final TextEditingController eventNameController = TextEditingController();
  final TextEditingController dateController = TextEditingController(
    text: "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
  );
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();
  final TextEditingController clientController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController materialsController = TextEditingController();
  final TextEditingController picturesController = TextEditingController();

  String? selectedJobType;

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
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
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
                              'Add New Event',
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
                            hintText: 'Event name*',
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: dateController,
                            hintText: 'Date',
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextField(
                                  controller: startTimeController,
                                  hintText: 'Start Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextField(
                                  controller: endTimeController,
                                  hintText: 'End Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: clientController,
                            hintText: 'Client (search by name or phone number)',
                          ),
                          SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: selectedJobType,
                            decoration: InputDecoration(
                              hintText: 'Type of job...',
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
                                borderSide: BorderSide(
                                  color: Color(0xFFD8D8D8),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: kPurple),
                              ),
                            ),
                            icon: Icon(Icons.keyboard_arrow_down_rounded),
                            items: [
                              DropdownMenuItem(
                                value: 'Item 1',
                                child: Text('Item 1'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 2',
                                child: Text('Item 2'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 3',
                                child: Text('Item 3'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 4',
                                child: Text('Item 4'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 5',
                                child: Text('Item 5'),
                              ),
                            ],
                            onChanged: (value) {
                              setPopupState(() {
                                selectedJobType = value;
                              });
                            },
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: noteController,
                            hintText: 'Type the note here...',
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: materialsController,
                            hintText: 'Type the materials here...',
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: picturesController,
                            hintText: 'Insert pictures here...',
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 16),
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
                              child: Text(
                                'Create Event',
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


Future<void> showAddEventDarkPopup(
    BuildContext context,
    DateTime selectedDate,
    ) async {
  final TextEditingController eventNameController = TextEditingController();
  final TextEditingController dateController = TextEditingController(
    text: "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
  );
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();
  final TextEditingController clientController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController materialsController = TextEditingController();
  final TextEditingController picturesController = TextEditingController();

  String? selectedJobType;

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
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
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
                              'Add New Event',
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
                            hintText: 'Event name*',
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: dateController,
                            hintText: 'Date',
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: startTimeController,
                                  hintText: 'Start Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: endTimeController,
                                  hintText: 'End Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: clientController,
                            hintText: 'Client (search by name or phone number)',
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: addressController,
                            hintText: 'Address',
                          ),
                          SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: selectedJobType,
                            dropdownColor: Color(0xFF171717),
                            style: TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Type of job...',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: 15,
                              ),
                              filled: true,
                              fillColor: Color(0xFF171717),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 16,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Color(0xFF2D2D2D),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: kPurple),
                              ),
                            ),
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'Item 1',
                                child: Text('Item 1'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 2',
                                child: Text('Item 2'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 3',
                                child: Text('Item 3'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 4',
                                child: Text('Item 4'),
                              ),
                              DropdownMenuItem(
                                value: 'Item 5',
                                child: Text('Item 5'),
                              ),
                            ],
                            onChanged: (value) {
                              setPopupState(() {
                                selectedJobType = value;
                              });
                            },
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: noteController,
                            hintText: 'Type the note here...',
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: materialsController,
                            hintText: 'Type the materials here...',
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: picturesController,
                            hintText: 'Insert pictures here...',
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 16),
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
                              child: Text(
                                'Create Event',
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
Future<void> showEditCalendarEventPopup(
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
  final noteController = TextEditingController(
    text: (event['notes'] ?? event['subtitle'] ?? '').toString(),
  );
  final materialsController = TextEditingController(
    text: (event['materials'] ?? '').toString(),
  );
  final picturesController = TextEditingController(
    text: (event['pictures'] ?? '').toString(),
  );

  String? selectedJobType = (event['jobType'] ?? '').toString().isEmpty
      ? null
      : (event['jobType'] ?? '').toString();

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
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
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
                              'Edit Event',
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
                            hintText: 'Event name',
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: dateController,
                            hintText: 'Date',
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextField(
                                  controller: startTimeController,
                                  hintText: 'Start Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextField(
                                  controller: endTimeController,
                                  hintText: 'End Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: clientController,
                            hintText: 'Client (search by name or phone number)',
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: addressController,
                            hintText: 'Address',
                          ),
                          SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: selectedJobType,
                            decoration: InputDecoration(
                              hintText: 'Type of job...',
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
                                borderSide: BorderSide(
                                  color: Color(0xFFD8D8D8),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: kPurple),
                              ),
                            ),
                            icon: Icon(Icons.keyboard_arrow_down_rounded),
                            items: [
                              DropdownMenuItem(value: 'Item 1', child: Text('Item 1')),
                              DropdownMenuItem(value: 'Item 2', child: Text('Item 2')),
                              DropdownMenuItem(value: 'Item 3', child: Text('Item 3')),
                              DropdownMenuItem(value: 'Item 4', child: Text('Item 4')),
                              DropdownMenuItem(value: 'Item 5', child: Text('Item 5')),
                            ],
                            onChanged: (value) {
                              setPopupState(() {
                                selectedJobType = value;
                              });
                            },
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: noteController,
                            hintText: 'Type the note here...',
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: materialsController,
                            hintText: 'Type the materials here...',
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextField(
                            controller: picturesController,
                            hintText: 'Insert pictures here...',
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                event['title'] = eventNameController.text.trim();
                                event['date'] = dateController.text.trim();
                                event['client'] = clientController.text.trim();
                                event['address'] = addressController.text.trim();
                                event['jobType'] = selectedJobType ?? '';
                                event['notes'] = noteController.text.trim();
                                event['materials'] = materialsController.text.trim();
                                event['pictures'] = picturesController.text.trim();
                                event['subtitle'] = noteController.text.trim();
                                final start = startTimeController.text.trim();
                                final end = endTimeController.text.trim();
                                event['time'] = start.isEmpty && end.isEmpty
                                    ? ''
                                    : end.isEmpty
                                    ? start
                                    : '$start-$end';
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
                              child: Text(
                                'Update Event',
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

Future<void> showEditCalendarEventDarkPopup(
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
  final noteController = TextEditingController(
    text: (event['notes'] ?? event['subtitle'] ?? '').toString(),
  );
  final materialsController = TextEditingController(
    text: (event['materials'] ?? '').toString(),
  );
  final picturesController = TextEditingController(
    text: (event['pictures'] ?? '').toString(),
  );

  String? selectedJobType = (event['jobType'] ?? '').toString().isEmpty
      ? null
      : (event['jobType'] ?? '').toString();

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
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
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
                              'Edit Event',
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
                            hintText: 'Event name',
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: dateController,
                            hintText: 'Date',
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: startTimeController,
                                  hintText: 'Start Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _popupTextFieldDark(
                                  controller: endTimeController,
                                  hintText: 'End Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: clientController,
                            hintText: 'Client (search by name or phone number)',
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: addressController,
                            hintText: 'Address',
                          ),
                          SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: selectedJobType,
                            dropdownColor: Color(0xFF171717),
                            style: TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Type of job...',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: 15,
                              ),
                              filled: true,
                              fillColor: Color(0xFF171717),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 16,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Color(0xFF2D2D2D),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: kPurple),
                              ),
                            ),
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                            ),
                            items: [
                              DropdownMenuItem(value: 'Item 1', child: Text('Item 1')),
                              DropdownMenuItem(value: 'Item 2', child: Text('Item 2')),
                              DropdownMenuItem(value: 'Item 3', child: Text('Item 3')),
                              DropdownMenuItem(value: 'Item 4', child: Text('Item 4')),
                              DropdownMenuItem(value: 'Item 5', child: Text('Item 5')),
                            ],
                            onChanged: (value) {
                              setPopupState(() {
                                selectedJobType = value;
                              });
                            },
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: noteController,
                            hintText: 'Type the note here...',
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: materialsController,
                            hintText: 'Type the materials here...',
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 14),
                          _popupTextFieldDark(
                            controller: picturesController,
                            hintText: 'Insert pictures here...',
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
                          ),
                          SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                event['title'] = eventNameController.text.trim();
                                event['date'] = dateController.text.trim();
                                event['client'] = clientController.text.trim();
                                event['address'] = addressController.text.trim();
                                event['jobType'] = selectedJobType ?? '';
                                event['notes'] = noteController.text.trim();
                                event['materials'] = materialsController.text.trim();
                                event['pictures'] = picturesController.text.trim();
                                event['subtitle'] = noteController.text.trim();
                                final start = startTimeController.text.trim();
                                final end = endTimeController.text.trim();
                                event['time'] = start.isEmpty && end.isEmpty
                                    ? ''
                                    : end.isEmpty
                                    ? start
                                    : '$start-$end';
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
                              child: Text(
                                'Update Event',
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

/* ---------------- CLIENTS LIGHT ---------------- */


Widget _popupTextField({
  required TextEditingController controller,
  required String hintText,
  IconData? suffixIcon,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Color(0xFF7A7A7A),
        fontSize: 15,
      ),
      suffixIcon: suffixIcon != null
          ? Icon(suffixIcon, color: Color(0xFF7A7A7A))
          : null,
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
    ),
  );
}

Widget _popupTextFieldDark({
  required TextEditingController controller,
  required String hintText,
  IconData? suffixIcon,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.white38,
        fontSize: 15,
      ),
      suffixIcon: suffixIcon != null
          ? Icon(suffixIcon, color: Colors.white54)
          : null,
      filled: true,
      fillColor: Color(0xFF171717),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 16,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

