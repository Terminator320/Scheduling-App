import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

const Color kPurple = Color(0xCC6D29F6);

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
      home: const LoginLightScreen(),
    );
  }
}

/* ---------------- LOGIN LIGHT ---------------- */

class LoginLightScreen extends StatelessWidget {
  const LoginLightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Login', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 10),
              const Text('Enter email and password'),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
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
                        builder: (context) => const AdminCalendarPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'Sign In',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateAccountLightScreen(),
                      ),
                    );
                  },
                  child: const Text(
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
      backgroundColor: const Color(0xFFF2F2F2),
      body: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create Account', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 10),
              const Text('Enter email and password'),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                  ),
                  onPressed: () {},
                  child: const Text(
                    'Create Account',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Login',
                style: TextStyle(fontSize: 22, color: Colors.white),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter email and password',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              const TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                obscureText: true,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
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
                        builder: (context) => const AdminCalendarDarkPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'Sign In',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Align(
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
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateAccountDarkScreen(),
                      ),
                    );
                  },
                  child: const Text(
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create Account',
                style: TextStyle(fontSize: 22, color: Colors.white),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter email and password',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              const TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                obscureText: true,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple,
                  ),
                  onPressed: () {},
                  child: const Text(
                    'Create Account',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
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
    showAddEventPopup(context);
  }

  @override
  Widget build(BuildContext context) {
    final calendarDays = buildCalendarDays(displayedMonth);
    final selectedEvents = events[dateKey(selectedDate)] ?? [];
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddEventPopup,
        backgroundColor: kPurple,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Row(
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
                  Icon(Icons.menu, size: 28),
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
              const Row(
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
                            decoration: const BoxDecoration(
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
                      const SizedBox(height: 8),
                      const Text(
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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7DDF9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event['time'] ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
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
          border: Border.all(color: const Color(0xFFD7D7D7)),
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
    showAddEventPopup(context);
  }

  @override
  Widget build(BuildContext context) {
    const Color background = Colors.black;
    const Color primaryText = Colors.white;
    const Color secondaryText = Color(0xFF9E9E9E);
    const Color fadedText = Color(0xFF5F5F5F);
    const Color dividerColor = Color(0xFF3A3A3A);
    const Color cardColor = kPurple;

    final calendarDays = buildCalendarDays(displayedMonth);
    final selectedEvents = events[dateKey(selectedDate)] ?? [];
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: background,
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddEventPopup,
        backgroundColor: kPurple,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Row(
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
                  Icon(Icons.menu, size: 28, color: primaryText),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: dividerColor),
              const SizedBox(height: 10),
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: primaryText,
                        ),
                      ),
                      Text(
                        '${displayedMonth.year}',
                        style: const TextStyle(
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
              const SizedBox(height: 18),
              const Row(
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
                                  ? Colors.white
                                  : fadedText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (hasEvents)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
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
              const SizedBox(height: 18),
              Expanded(
                child: selectedEvents.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.event_note_rounded,
                        size: 42,
                        color: fadedText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No events for ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: secondaryText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event['time'] ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFFD8CFFF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            event['title'] ?? '',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          if ((event['subtitle'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              event['subtitle'],
                              style: const TextStyle(
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
          border: Border.all(color: const Color(0xFF4A4A4A)),
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

/* ---------------- POPUP ---------------- */

Future<void> showAddEventPopup(BuildContext context) async {
  final TextEditingController eventNameController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
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
                decoration: const BoxDecoration(
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
                          const Center(
                            child: SizedBox(
                              width: 44,
                              child: Divider(
                                thickness: 4,
                                color: Color(0xFFD0D0D0),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Center(
                            child: Text(
                              'Add New Event',
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
                            hintText: 'Event name*',
                          ),
                          const SizedBox(height: 14),

                          _popupTextField(
                            controller: dateController,
                            hintText: 'Date',
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          const SizedBox(height: 14),

                          Row(
                            children: [
                              Expanded(
                                child: _popupTextField(
                                  controller: startTimeController,
                                  hintText: 'Start Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _popupTextField(
                                  controller: endTimeController,
                                  hintText: 'End Time',
                                  suffixIcon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          _popupTextField(
                            controller: clientController,
                            hintText: 'Client (search by name or phone number)',
                          ),
                          const SizedBox(height: 14),

                          DropdownButtonFormField<String>(
                            value: selectedJobType,
                            decoration: InputDecoration(
                              hintText: 'Type of job...',
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
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8D8D8),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: kPurple),
                              ),
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            items: const [
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
                          const SizedBox(height: 14),

                          _popupTextField(
                            controller: noteController,
                            hintText: 'Type the note here...',
                            suffixIcon: Icons.note_alt_outlined,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 14),

                          _popupTextField(
                            controller: materialsController,
                            hintText: 'Type the materials here...',
                            suffixIcon: Icons.build_outlined,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 14),

                          _popupTextField(
                            controller: picturesController,
                            hintText: 'Insert pictures here...',
                            suffixIcon: Icons.image_outlined,
                            maxLines: 3,
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
                                'Create Event',
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
      hintStyle: const TextStyle(
        color: Color(0xFF7A7A7A),
        fontSize: 15,
      ),
      suffixIcon: suffixIcon != null
          ? Icon(suffixIcon, color: const Color(0xFF7A7A7A))
          : null,
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
        borderSide: const BorderSide(color: kPurple),
      ),
    ),
  );
}