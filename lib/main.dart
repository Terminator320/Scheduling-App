import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

Color kPurple = Color(0xCC6D29F6);


class EmployeeRecord {
  EmployeeRecord({
    required this.name,
    required this.email,
    required this.phone,
    required this.color,
  });

  String name;
  String email;
  String phone;
  Color color;
}

final List<EmployeeRecord> kEmployees = [
  EmployeeRecord(
    name: 'Emma Carter',
    email: 'employee@email.com',
    phone: '(514) 555-0134',
    color: kEmployeePickerColors[6],
  ),
  EmployeeRecord(
    name: 'Noah Tremblay',
    email: 'employee@email.com',
    phone: '(514) 555-0148',
    color: kEmployeePickerColors[1],
  ),
  EmployeeRecord(
    name: 'Olivia Martin',
    email: 'employee@email.com',
    phone: '(514) 555-0162',
    color: kEmployeePickerColors[2],
  ),
  EmployeeRecord(
    name: 'Liam Roy',
    email: 'employee@email.com',
    phone: '(514) 555-0189',
    color: kEmployeePickerColors[3],
  ),
  EmployeeRecord(
    name: 'Charlotte Gagnon',
    email: 'employee@email.com',
    phone: '(514) 555-0197',
    color: kEmployeePickerColors[7],
  ),
];

const List<Color> kEmployeePickerColors = [
  Colors.black,
  Color(0xFF1D8CFF),
  Color(0xFF42C86A),
  Color(0xFFF4C20D),
  Color(0xFFFF3B30),
  Color(0xFF7DC9FF),
  Color(0xFFB455FF),
  Color(0xFF5C6BFF),
  Color(0xFFFF2D55),
];

Color employeeCardColor(Color color) {
  return Color.alphaBlend(color.withOpacity(0.22), Colors.white);
}

Color employeeCardTextColor(Color color) {
  final brightness = ThemeData.estimateBrightnessForColor(color);
  return brightness == Brightness.dark ? Colors.white : Colors.black;
}

Color employeeCardSubtextColor(Color color) {
  final brightness = ThemeData.estimateBrightnessForColor(color);
  return brightness == Brightness.dark ? Colors.white70 : Colors.black54;
}

class ClientRecord {
  ClientRecord({
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
  });

  String name;
  String phone;
  String email;
  String address;
}

final List<ClientRecord> kClients = [
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0112',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0135',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0174',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0180',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
  ClientRecord(
    name: 'Client name',
    phone: '(514) 555-0193',
    email: 'client@email.com',
    address: '123 Main Street',
  ),
];


class AppointmentRecord {
  AppointmentRecord({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.clientName,
    required this.clientPhone,
    required this.address,
    required this.jobType,
    required this.notes,
    required this.materialsNeeded,
    required this.pictures,
  });

  final String title;
  final String date;
  final String startTime;
  final String endTime;
  final String clientName;
  final String clientPhone;
  final String address;
  final String jobType;
  final String notes;
  final String materialsNeeded;
  final String pictures;
}

final List<AppointmentRecord> kAppointments = [
  AppointmentRecord(
    title: 'Job title',
    date: 'May 20, 2026',
    startTime: '9:00 AM',
    endTime: '10:00 AM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0112',
    address: '123 Main Street',
    jobType: 'Item 1',
    notes: 'General appointment notes',
    materialsNeeded: 'Standard tools',
    pictures: 'No pictures added',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 20, 2026',
    startTime: '11:00 AM',
    endTime: '12:00 PM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0135',
    address: '456 Park Avenue',
    jobType: 'Item 2',
    notes: 'Customer requested confirmation call',
    materialsNeeded: 'Replacement parts',
    pictures: '2 pictures attached',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 21, 2026',
    startTime: '1:30 PM',
    endTime: '2:30 PM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0174',
    address: '789 Elm Street',
    jobType: 'Item 3',
    notes: 'Access through side entrance',
    materialsNeeded: 'Inspection checklist',
    pictures: 'No pictures added',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 21, 2026',
    startTime: '3:00 PM',
    endTime: '4:00 PM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0180',
    address: '22 Cedar Road',
    jobType: 'Item 4',
    notes: 'Call on arrival',
    materialsNeeded: 'Cleaning supplies',
    pictures: '1 picture attached',
  ),
  AppointmentRecord(
    title: 'Job title',
    date: 'May 22, 2026',
    startTime: '8:30 AM',
    endTime: '9:30 AM',
    clientName: 'Client name',
    clientPhone: '(514) 555-0193',
    address: '98 River Lane',
    jobType: 'Item 5',
    notes: 'Bring extra materials',
    materialsNeeded: 'Extra fittings',
    pictures: '3 pictures attached',
  ),
];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scheduling App',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: LoginLightScreen(),
    );
  }
}

/* ---------------- LOGIN LIGHT ---------------- */

class LoginLightScreen extends StatelessWidget {
  const LoginLightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF2F2F2),
      body: Center(
        child: Container(
          width: 320,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Login', style: TextStyle(fontSize: 22)),
              SizedBox(height: 10),
              Text('Enter email and password'),
              SizedBox(height: 20),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminCalendarPage(),
                      ),
                    );
                  },
                  child: Text(
                    'Sign In',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateAccountLightScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Create account',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CREATE ACCOUNT LIGHT ---------------- */

class CreateAccountLightScreen extends StatelessWidget {
  const CreateAccountLightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF2F2F2),
      body: Center(
        child: Container(
          width: 320,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create Account', style: TextStyle(fontSize: 22)),
              SizedBox(height: 10),
              Text('Enter email and password'),
              SizedBox(height: 20),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                  ),
                  onPressed: () {},
                  child: Text(
                    'Create Account',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Sign in',
                    style: TextStyle(
                      color: Colors.black,
                      decoration: TextDecoration.underline,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- LOGIN DARK ---------------- */

class LoginDarkScreen extends StatelessWidget {
  const LoginDarkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          width: 320,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Login',
                style: TextStyle(fontSize: 22, color: Colors.white),
              ),
              SizedBox(height: 10),
              Text(
                'Enter email and password',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 20),
              TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                obscureText: true,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminCalendarDarkPage(),
                      ),
                    );
                  },
                  child: Text(
                    'Sign In',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: Colors.white,
                    decoration: TextDecoration.underline,
                    decorationThickness: 2,
                  ),
                ),
              ),
              SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateAccountDarkScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Create account',
                    style: TextStyle(
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CREATE ACCOUNT DARK ---------------- */

class CreateAccountDarkScreen extends StatelessWidget {
  const CreateAccountDarkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          width: 320,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create Account',
                style: TextStyle(fontSize: 22, color: Colors.white),
              ),
              SizedBox(height: 10),
              Text(
                'Enter email and password',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 20),
              TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                obscureText: true,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                  ),
                  onPressed: () {},
                  child: Text(
                    'Create Account',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Sign in',
                    style: TextStyle(
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- ADMIN CALENDAR PAGE LIGHT ---------------- */

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

class AdminMenuDrawer extends StatelessWidget {
  const AdminMenuDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 260,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Text(
                '(Admin Name)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Divider(height: 1),
            _DrawerMenuItem(
              icon: Icons.person_outline,
              title: 'Profile',
              onTap: () {
                Navigator.pop(context);
              },
            ),
            _DrawerMenuItem(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminCalendarPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItem(
              icon: Icons.badge_outlined,
              title: 'Employees',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminEmployeesPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItem(
              icon: Icons.group_outlined,
              title: 'Clients',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminClientsPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItem(
              icon: Icons.event_note_outlined,
              title: 'Appointments',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminAppointmentsPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItem(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminSettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- RIGHT MENU DARK ---------------- */

class AdminMenuDrawerDark extends StatelessWidget {
  const AdminMenuDrawerDark({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 260,
      backgroundColor: Color(0xFF111111),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Text(
                '(Admin Name)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Divider(height: 1, color: Color(0xFF2E2E2E)),
            _DrawerMenuItemDark(
              icon: Icons.person_outline,
              title: 'Profile',
              onTap: () {
                Navigator.pop(context);
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminCalendarDarkPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.badge_outlined,
              title: 'Employees',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminEmployeesDarkPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.group_outlined,
              title: 'Clients',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminClientsDarkPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.event_note_outlined,
              title: 'Appointments',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminAppointmentsDarkPage(),
                  ),
                );
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminSettingsDarkPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.black54),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: Colors.black87,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _DrawerMenuItemDark extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerMenuItemDark({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
        ),
      ),
      onTap: onTap,
    );
  }
}



/* ---------------- EMPLOYEES LIGHT ---------------- */

class AdminEmployeesPage extends StatefulWidget {
  const AdminEmployeesPage({super.key});

  @override
  State<AdminEmployeesPage> createState() => _AdminEmployeesPageState();
}

class _AdminEmployeesPageState extends State<AdminEmployeesPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeeRecord> get filteredEmployees {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kEmployees;
    return kEmployees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          employee.phone.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final employees = filteredEmployees;

    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>  CreateEmployeePage(),
            ),
          );
          setState(() {});
        },
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
                    'Edit Employees',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
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
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number',
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: employees.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    return _EmployeeCard(
                      employee: employee,
                      onEdit: () async {
                        await showEditEmployeePopup(context, employee: employee);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kEmployees.remove(employee);
                        });
                      },
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

/* ---------------- EMPLOYEES DARK ---------------- */

class AdminEmployeesDarkPage extends StatefulWidget {
  const AdminEmployeesDarkPage({super.key});

  @override
  State<AdminEmployeesDarkPage> createState() => _AdminEmployeesDarkPageState();
}

class _AdminEmployeesDarkPageState extends State<AdminEmployeesDarkPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EmployeeRecord> get filteredEmployees {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kEmployees;
    return kEmployees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          employee.phone.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final employees = filteredEmployees;

    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateEmployeeDarkPage(),
            ),
          );
          setState(() {});
        },
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
                    'Edit Employees',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
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
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number',
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Color(0xFF171717),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFF2D2D2D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: employees.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    return _EmployeeCardDark(
                      employee: employee,
                      onEdit: () async {
                        await showEditEmployeeDarkPopup(context, employee: employee);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kEmployees.remove(employee);
                        });
                      },
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

/* ---------------- CREATE EMPLOYEE LIGHT ---------------- */

class CreateEmployeePage extends StatefulWidget {
  const CreateEmployeePage({super.key});

  @override
  State<CreateEmployeePage> createState() => _CreateEmployeePageState();
}

class _CreateEmployeePageState extends State<CreateEmployeePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  Color _selectedColor = kEmployeePickerColors[1];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Create Employee',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 10),
              Text('Enter username and email'),
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE1E1E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Username'),
                    SizedBox(height: 8),
                    _employeeFormField(controller: _nameController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Email'),
                    SizedBox(height: 8),
                    _employeeFormField(controller: _emailController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Phone number'),
                    SizedBox(height: 8),
                    _employeeFormField(controller: _phoneController, hintText: 'Value'),
                    SizedBox(height: 18),
                    Text('Employee Color'),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: kEmployeePickerColors.map((color) {
                        final isSelected = _selectedColor == color;
                        return _ColorDot(
                          color: color,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            kEmployees.add(
                              EmployeeRecord(
                                name: _nameController.text.trim().isEmpty
                                    ? 'Employee name'
                                    : _nameController.text.trim(),
                                email: _emailController.text.trim().isEmpty
                                    ? 'employee@email.com'
                                    : _emailController.text.trim(),
                                phone: _phoneController.text.trim().isEmpty
                                    ? '(000) 000-0000'
                                    : _phoneController.text.trim(),
                                color: _selectedColor,
                              ),
                            );
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Create Employee'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CREATE EMPLOYEE DARK ---------------- */

class CreateEmployeeDarkPage extends StatefulWidget {
  const CreateEmployeeDarkPage({super.key});

  @override
  State<CreateEmployeeDarkPage> createState() => _CreateEmployeeDarkPageState();
}

class _CreateEmployeeDarkPageState extends State<CreateEmployeeDarkPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  Color _selectedColor = kEmployeePickerColors[1];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'Create Employee',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 10),
              Text('Enter username and email', style: TextStyle(color: Colors.white70)),
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Username', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 8),
                    _employeeFormFieldDark(controller: _nameController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Email', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 8),
                    _employeeFormFieldDark(controller: _emailController, hintText: 'Value'),
                    SizedBox(height: 14),
                    Text('Phone number', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 8),
                    _employeeFormFieldDark(controller: _phoneController, hintText: 'Value'),
                    SizedBox(height: 18),
                    Text('Employee Color', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: kEmployeePickerColors.map((color) {
                        final isSelected = _selectedColor == color;
                        return _ColorDot(
                          color: color,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            kEmployees.add(
                              EmployeeRecord(
                                name: _nameController.text.trim().isEmpty
                                    ? 'Employee name'
                                    : _nameController.text.trim(),
                                email: _emailController.text.trim().isEmpty
                                    ? 'employee@email.com'
                                    : _emailController.text.trim(),
                                phone: _phoneController.text.trim().isEmpty
                                    ? '(000) 000-0000'
                                    : _phoneController.text.trim(),
                                color: _selectedColor,
                              ),
                            );
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Create Employee'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- SETTINGS LIGHT ---------------- */

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
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
                    'Settings',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE1E1E1)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.description_outlined),
                      title: Text('Change Font Size'),
                      onTap: () {},
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.dark_mode_outlined),
                      title: Text('Change to Dark Mode'),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminSettingsDarkPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- SETTINGS DARK ---------------- */

class AdminSettingsDarkPage extends StatelessWidget {
  const AdminSettingsDarkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
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
                    'Settings',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.description_outlined, color: Colors.white70),
                      title: Text('Change Font Size', style: TextStyle(color: Colors.white)),
                      onTap: () {},
                    ),
                    Divider(height: 1, color: Color(0xFF2A2A2A)),
                    ListTile(
                      leading: Icon(Icons.light_mode_outlined, color: Colors.white70),
                      title: Text('Change to Light Mode', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminSettingsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final EmployeeRecord employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCard({
    required this.employee,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: employeeCardColor(employee.color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: employeeCardTextColor(employee.color),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  employee.email,
                  style: TextStyle(
                    fontSize: 11,
                    color: employeeCardSubtextColor(employee.color),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _EmployeeCardDark extends StatelessWidget {
  final EmployeeRecord employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCardDark({
    required this.employee,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Color(0xFF171717),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 44,
            decoration: BoxDecoration(
              color: employee.color.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  employee.email,
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20, color: Colors.white70),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? kPurple : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}

Widget _employeeFormField({
  required TextEditingController controller,
  required String hintText,
}) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Widget _employeeFormFieldDark({
  required TextEditingController controller,
  required String hintText,
}) {
  return TextField(
    controller: controller,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Color(0xFF171717),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Future<void> showEditEmployeePopup(
    BuildContext context, {
      required EmployeeRecord employee,
    }) async {
  final nameController = TextEditingController(text: employee.name);
  final phoneController = TextEditingController(text: employee.phone);
  final emailController = TextEditingController(text: employee.email);
  Color selectedColor = employee.color;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Divider(thickness: 4, color: Color(0xFFD0D0D0)),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Edit Employee',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 18),
                    _employeeFormField(controller: nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _employeeFormField(controller: phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _employeeFormField(controller: emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Employee Color',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kEmployeePickerColors.map((color) {
                        return _ColorDot(
                          color: color,
                          isSelected: selectedColor.value == color.value,
                          onTap: () {
                            setModalState(() {
                              selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          employee.name = nameController.text.trim().isEmpty
                              ? employee.name
                              : nameController.text.trim();
                          employee.phone = phoneController.text.trim().isEmpty
                              ? employee.phone
                              : phoneController.text.trim();
                          employee.email = emailController.text.trim().isEmpty
                              ? employee.email
                              : emailController.text.trim();
                          employee.color = selectedColor;
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Update Employee'),
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

Future<void> showEditEmployeeDarkPopup(
    BuildContext context, {
      required EmployeeRecord employee,
    }) async {
  final nameController = TextEditingController(text: employee.name);
  final phoneController = TextEditingController(text: employee.phone);
  final emailController = TextEditingController(text: employee.email);
  Color selectedColor = employee.color;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Divider(thickness: 4, color: Color(0xFF3A3A3A)),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Edit Employee',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 18),
                    _employeeFormFieldDark(controller: nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _employeeFormFieldDark(controller: phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _employeeFormFieldDark(controller: emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Employee Color',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kEmployeePickerColors.map((color) {
                        return _ColorDot(
                          color: color,
                          isSelected: selectedColor.value == color.value,
                          onTap: () {
                            setModalState(() {
                              selectedColor = color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          employee.name = nameController.text.trim().isEmpty
                              ? employee.name
                              : nameController.text.trim();
                          employee.phone = phoneController.text.trim().isEmpty
                              ? employee.phone
                              : phoneController.text.trim();
                          employee.email = emailController.text.trim().isEmpty
                              ? employee.email
                              : emailController.text.trim();
                          employee.color = selectedColor;
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Update Employee'),
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

/* ---------------- POPUP ---------------- */

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

class AdminClientsPage extends StatefulWidget {
  const AdminClientsPage({super.key});

  @override
  State<AdminClientsPage> createState() => _AdminClientsPageState();
}

class _AdminClientsPageState extends State<AdminClientsPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClientRecord> get filteredClients {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kClients;
    return kClients.where((client) {
      return client.name.toLowerCase().contains(query) ||
          client.phone.toLowerCase().contains(query) ||
          client.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clients = filteredClients;

    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClientPage(),
            ),
          );
          setState(() {});
        },
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
                    'Edit Clients',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
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
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: clients.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    return _ClientCard(
                      client: client,
                      onEdit: () async {
                        await showEditClientPopup(context, client: client);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kClients.remove(client);
                        });
                      },
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

/* ---------------- CLIENTS DARK ---------------- */

class AdminClientsDarkPage extends StatefulWidget {
  const AdminClientsDarkPage({super.key});

  @override
  State<AdminClientsDarkPage> createState() => _AdminClientsDarkPageState();
}

class _AdminClientsDarkPageState extends State<AdminClientsDarkPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClientRecord> get filteredClients {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return kClients;
    return kClients.where((client) {
      return client.name.toLowerCase().contains(query) ||
          client.phone.toLowerCase().contains(query) ||
          client.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clients = filteredClients;

    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: const AdminMenuDrawerDark(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClientDarkPage(),
            ),
          );
          setState(() {});
        },
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
                    'Edit Clients',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
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
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Color(0xFF171717),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFF2D2D2D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: clients.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    return _ClientCardDark(
                      client: client,
                      onEdit: () async {
                        await showEditClientDarkPopup(context, client: client);
                        setState(() {});
                      },
                      onDelete: () {
                        setState(() {
                          kClients.remove(client);
                        });
                      },
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

/* ---------------- CREATE CLIENT LIGHT ---------------- */

class CreateClientPage extends StatefulWidget {
  const CreateClientPage({super.key});

  @override
  State<CreateClientPage> createState() => _CreateClientPageState();
}

class _CreateClientPageState extends State<CreateClientPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Add Client',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 18),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE0E0E0)),
                ),
                child: Column(
                  children: [
                    _clientFormField(controller: _nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _clientFormField(
                      controller: _addressController,
                      hintText: 'Address',
                      maxLines: 2,
                    ),
                    SizedBox(height: 12),
                    _clientFormField(controller: _phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _clientFormField(controller: _emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          kClients.add(
                            ClientRecord(
                              name: _nameController.text.trim().isEmpty
                                  ? 'Client name'
                                  : _nameController.text.trim(),
                              address: _addressController.text.trim().isEmpty
                                  ? '123 Main Street'
                                  : _addressController.text.trim(),
                              phone: _phoneController.text.trim().isEmpty
                                  ? '(514) 555-0000'
                                  : _phoneController.text.trim(),
                              email: _emailController.text.trim().isEmpty
                                  ? 'client@email.com'
                                  : _emailController.text.trim(),
                            ),
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Add Client'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CREATE CLIENT DARK ---------------- */

class CreateClientDarkPage extends StatefulWidget {
  const CreateClientDarkPage({super.key});

  @override
  State<CreateClientDarkPage> createState() => _CreateClientDarkPageState();
}

class _CreateClientDarkPageState extends State<CreateClientDarkPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'Add Client',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 18),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF111111),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  children: [
                    _clientFormFieldDark(controller: _nameController, hintText: 'name'),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      controller: _addressController,
                      hintText: 'Address',
                      maxLines: 2,
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(controller: _phoneController, hintText: 'Phone number'),
                    SizedBox(height: 12),
                    _clientFormFieldDark(controller: _emailController, hintText: 'Email'),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          kClients.add(
                            ClientRecord(
                              name: _nameController.text.trim().isEmpty
                                  ? 'Client name'
                                  : _nameController.text.trim(),
                              address: _addressController.text.trim().isEmpty
                                  ? '123 Main Street'
                                  : _addressController.text.trim(),
                              phone: _phoneController.text.trim().isEmpty
                                  ? '(514) 555-0000'
                                  : _phoneController.text.trim(),
                              email: _emailController.text.trim().isEmpty
                                  ? 'client@email.com'
                                  : _emailController.text.trim(),
                            ),
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Add Client'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final ClientRecord client;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientCard({
    required this.client,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Color(0xFFDCD4F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  client.phone,
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ClientCardDark extends StatelessWidget {
  final ClientRecord client;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientCardDark({
    required this.client,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Color(0xFF171717),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  client.phone,
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 20, color: Colors.white70),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

Widget _clientFormField({
  required TextEditingController controller,
  required String hintText,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    decoration: InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Widget _clientFormFieldDark({
  required TextEditingController controller,
  required String hintText,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Color(0xFF171717),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPurple),
      ),
    ),
  );
}

Future<void> showEditClientPopup(
    BuildContext context, {
      required ClientRecord client,
    }) async {
  final nameController = TextEditingController(text: client.name);
  final addressController = TextEditingController(text: client.address);
  final phoneController = TextEditingController(text: client.phone);
  final emailController = TextEditingController(text: client.email);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFFD0D0D0)),
              ),
              SizedBox(height: 12),
              Text(
                'Edit Client',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 18),
              _clientFormField(controller: nameController, hintText: 'name'),
              SizedBox(height: 12),
              _clientFormField(
                controller: addressController,
                hintText: 'Address',
                maxLines: 2,
              ),
              SizedBox(height: 12),
              _clientFormField(controller: phoneController, hintText: 'Phone number'),
              SizedBox(height: 12),
              _clientFormField(controller: emailController, hintText: 'Email'),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    client.name = nameController.text.trim().isEmpty
                        ? client.name
                        : nameController.text.trim();
                    client.address = addressController.text.trim().isEmpty
                        ? client.address
                        : addressController.text.trim();
                    client.phone = phoneController.text.trim().isEmpty
                        ? client.phone
                        : phoneController.text.trim();
                    client.email = emailController.text.trim().isEmpty
                        ? client.email
                        : emailController.text.trim();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Update Client'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showEditClientDarkPopup(
    BuildContext context, {
      required ClientRecord client,
    }) async {
  final nameController = TextEditingController(text: client.name);
  final addressController = TextEditingController(text: client.address);
  final phoneController = TextEditingController(text: client.phone);
  final emailController = TextEditingController(text: client.email);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFF3A3A3A)),
              ),
              SizedBox(height: 12),
              Text(
                'Edit Client',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 18),
              _clientFormFieldDark(controller: nameController, hintText: 'name'),
              SizedBox(height: 12),
              _clientFormFieldDark(
                controller: addressController,
                hintText: 'Address',
                maxLines: 2,
              ),
              SizedBox(height: 12),
              _clientFormFieldDark(controller: phoneController, hintText: 'Phone number'),
              SizedBox(height: 12),
              _clientFormFieldDark(controller: emailController, hintText: 'Email'),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    client.name = nameController.text.trim().isEmpty
                        ? client.name
                        : nameController.text.trim();
                    client.address = addressController.text.trim().isEmpty
                        ? client.address
                        : addressController.text.trim();
                    client.phone = phoneController.text.trim().isEmpty
                        ? client.phone
                        : phoneController.text.trim();
                    client.email = emailController.text.trim().isEmpty
                        ? client.email
                        : emailController.text.trim();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Update Client'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

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


/* ---------------- APPOINTMENTS LIGHT ---------------- */

class AdminAppointmentsPage extends StatefulWidget {
  const AdminAppointmentsPage({super.key});

  @override
  State<AdminAppointmentsPage> createState() => _AdminAppointmentsPageState();
}

class _AdminAppointmentsPageState extends State<AdminAppointmentsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppointmentRecord> get _filteredAppointments {
    if (_query.trim().isEmpty) {
      return kAppointments;
    }

    final q = _query.toLowerCase().trim();
    return kAppointments.where((appointment) {
      return appointment.title.toLowerCase().contains(q) ||
          appointment.clientName.toLowerCase().contains(q) ||
          appointment.clientPhone.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _filteredAppointments;

    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: AdminMenuDrawer(),
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
                    'Appointments',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28, color: Colors.black87),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.black38),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFFDCDCDC)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: appointments.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final appointment = appointments[index];
                    return _AppointmentCard(
                      appointment: appointment,
                      onTap: () => showAppointmentInfoPopup(
                        context,
                        appointment: appointment,
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

/* ---------------- APPOINTMENTS DARK ---------------- */

class AdminAppointmentsDarkPage extends StatefulWidget {
  const AdminAppointmentsDarkPage({super.key});

  @override
  State<AdminAppointmentsDarkPage> createState() => _AdminAppointmentsDarkPageState();
}

class _AdminAppointmentsDarkPageState extends State<AdminAppointmentsDarkPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppointmentRecord> get _filteredAppointments {
    if (_query.trim().isEmpty) {
      return kAppointments;
    }

    final q = _query.toLowerCase().trim();
    return kAppointments.where((appointment) {
      return appointment.title.toLowerCase().contains(q) ||
          appointment.clientName.toLowerCase().contains(q) ||
          appointment.clientPhone.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _filteredAppointments;

    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
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
                    'Appointments',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
              SizedBox(height: 16),
              TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.white38),
                  filled: true,
                  fillColor: Color(0xFF171717),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: appointments.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final appointment = appointments[index];
                    return _AppointmentCardDark(
                      appointment: appointment,
                      onTap: () => showAppointmentInfoDarkPopup(
                        context,
                        appointment: appointment,
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

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.onTap,
  });

  final AppointmentRecord appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color(0xFFDCD4F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${appointment.clientName} (${appointment.clientPhone})',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Text(
                appointment.date,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentCardDark extends StatelessWidget {
  const _AppointmentCardDark({
    required this.appointment,
    required this.onTap,
  });

  final AppointmentRecord appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color(0xFF171717),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Color(0xFF2A2A2A)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(0xFFDCD4F8),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${appointment.clientName} (${appointment.clientPhone})',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Text(
                appointment.date,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _appointmentInfoField({
  required String value,
  required String hintText,
  IconData? icon,
}) {
  return TextField(
    controller: TextEditingController(text: value),
    readOnly: true,
    decoration: InputDecoration(
      hintText: hintText,
      suffixIcon: icon != null ? Icon(icon, size: 18, color: Colors.black45) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
    ),
  );
}

Widget _appointmentInfoFieldDark({
  required String value,
  required String hintText,
  IconData? icon,
}) {
  return TextField(
    controller: TextEditingController(text: value),
    readOnly: true,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.white38),
      suffixIcon: icon != null ? Icon(icon, size: 18, color: Colors.white54) : null,
      filled: true,
      fillColor: Color(0xFF171717),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
    ),
  );
}

Future<void> showAppointmentInfoPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFFD0D0D0)),
              ),
              SizedBox(height: 12),
              Text(
                'Event',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _appointmentInfoField(
                        value: appointment.title,
                        hintText: 'Event name',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.date,
                        hintText: 'Date',
                        icon: Icons.calendar_today_outlined,
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _appointmentInfoField(
                              value: appointment.startTime,
                              hintText: 'Start Time',
                              icon: Icons.access_time,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _appointmentInfoField(
                              value: appointment.endTime,
                              hintText: 'End Time',
                              icon: Icons.access_time,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: '${appointment.clientName} (${appointment.clientPhone})',
                        hintText: 'Client name (phone number)',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.address,
                        hintText: 'Address',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.jobType,
                        hintText: 'Type of job',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.notes,
                        hintText: 'Notes',
                        icon: Icons.description_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.materialsNeeded,
                        hintText: 'Materials needed',
                        icon: Icons.build_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.pictures,
                        hintText: 'Pictures',
                        icon: Icons.image_outlined,
                      ),
                    ],
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

Future<void> showAppointmentInfoDarkPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFF3A3A3A)),
              ),
              SizedBox(height: 12),
              Text(
                'Event',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _appointmentInfoFieldDark(
                        value: appointment.title,
                        hintText: 'Event name',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.date,
                        hintText: 'Date',
                        icon: Icons.calendar_today_outlined,
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _appointmentInfoFieldDark(
                              value: appointment.startTime,
                              hintText: 'Start Time',
                              icon: Icons.access_time,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _appointmentInfoFieldDark(
                              value: appointment.endTime,
                              hintText: 'End Time',
                              icon: Icons.access_time,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: '${appointment.clientName} (${appointment.clientPhone})',
                        hintText: 'Client name (phone number)',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.address,
                        hintText: 'Address',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.jobType,
                        hintText: 'Type of job',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.notes,
                        hintText: 'Notes',
                        icon: Icons.description_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.materialsNeeded,
                        hintText: 'Materials needed',
                        icon: Icons.build_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.pictures,
                        hintText: 'Pictures',
                        icon: Icons.image_outlined,
                      ),
                    ],
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
