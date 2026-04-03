import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CalendarView extends StatefulWidget {
  final String employeeId;
  final String? employeeName;

  const CalendarView({
    super.key,
    required this.employeeId,
    this.employeeName,
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calendar'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Welcome ${widget.employeeName ?? "Employee"}'),
            SizedBox(height: 15,),
            Container(
              height: 200,
              width: 200,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Center(
                child: Text(
                  "Hello word",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),

          ],
        )
      ),
    );
  }
}
