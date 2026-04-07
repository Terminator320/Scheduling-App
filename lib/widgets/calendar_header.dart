import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CalendarHeader extends StatelessWidget {
  final DateTime focusedDay;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onToday;
  final VoidCallback onTapMonth;

  const CalendarHeader({
    super.key,
    required this.focusedDay,
    required this.onLeft,
    required this.onRight,
    required this.onToday,
    required this.onTapMonth,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent =
        focusedDay.year == now.year && focusedDay.month == now.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onLeft),

          GestureDetector(
            onTap: onTapMonth,
            child: Text(
              DateFormat('MMMM').format(focusedDay),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isCurrent ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),

          Row(
            children: [
              if (!isCurrent)
                TextButton(onPressed: onToday, child: const Text("Today")),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: onRight,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
