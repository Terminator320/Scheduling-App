import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    required this.focusedDay, required this.onLeft, required this.onRight, required this.onToday, required this.onTapMonth, super.key,
  });
  final DateTime focusedDay;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onToday;
  final VoidCallback onTapMonth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent =
        focusedDay.year == now.year && focusedDay.month == now.month;
    final locale = Localizations.localeOf(context).toString();
    final monthLabel = DateFormat.MMMM(locale).format(focusedDay);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onLeft),

          GestureDetector(
            onTap: onTapMonth,
            child: Text(
              monthLabel,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isCurrent
                    ? AppColors.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),

          Row(
            children: [
              if (!isCurrent)
                TextButton(
                  onPressed: onToday,
                  child: Text(context.l10n.today),
                ),
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
