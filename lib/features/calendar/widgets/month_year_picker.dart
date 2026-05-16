import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/utils/l10n_extensions.dart';

class MonthYearPicker {
  static const int _startYear = 2000;
  static const int _yearCount = 30;

  static Future<DateTime?> show(
    BuildContext context,
    DateTime focusedDay,
  ) async {
    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MonthYearPickerContent(focusedDay: focusedDay),
    );
  }
}

class _MonthYearPickerContent extends StatefulWidget {
  const _MonthYearPickerContent({required this.focusedDay});
  final DateTime focusedDay;

  @override
  State<_MonthYearPickerContent> createState() =>
      _MonthYearPickerContentState();
}

class _MonthYearPickerContentState extends State<_MonthYearPickerContent> {
  late int selectedMonth;
  late int selectedYear;

  @override
  void initState() {
    super.initState();
    selectedMonth = widget.focusedDay.month;
    selectedYear = widget.focusedDay.year;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyLarge = theme.textTheme.bodyLarge;
    final monthFormat = DateFormat.MMMM(locale);

    return SizedBox(
      height: 300,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text(
                    context.l10n.cancel,
                    style: TextStyle(color: scheme.primary),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text(
                    context.l10n.done,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    DateTime(selectedYear, selectedMonth),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: selectedMonth - 1,
                    ),
                    itemExtent: 40,
                    useMagnifier: true,
                    magnification: 1.2,
                    squeeze: 1.2,
                    onSelectedItemChanged: (i) => selectedMonth = i + 1,
                    children: List.generate(
                      12,
                      (i) => Center(
                        child: Text(
                          monthFormat.format(DateTime(0, i + 1)),
                          style: bodyLarge,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: selectedYear - MonthYearPicker._startYear,
                    ),
                    itemExtent: 40,
                    useMagnifier: true,
                    magnification: 1.2,
                    squeeze: 1.2,
                    onSelectedItemChanged: (i) =>
                        selectedYear = MonthYearPicker._startYear + i,
                    children: List.generate(
                      MonthYearPicker._yearCount,
                      (i) => Center(
                        child: Text(
                          '${MonthYearPicker._startYear + i}',
                          style: bodyLarge,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
