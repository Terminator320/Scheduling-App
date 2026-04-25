import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';

class MonthYearPicker {
  static const int _startYear = 2000;
  static const int _yearCount = 30;

  static Future<DateTime?> show(
    BuildContext context,
    DateTime focusedDay,
  ) async {
    return await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MonthYearPickerContent(focusedDay: focusedDay),
    );
  }
}

class _MonthYearPickerContent extends StatefulWidget {
  final DateTime focusedDay;

  const _MonthYearPickerContent({required this.focusedDay});

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
                    'Cancel',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
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
                    selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(),
                    onSelectedItemChanged: (i) => selectedMonth = i + 1,
                    children: List.generate(
                      12,
                      (i) => Center(
                        child: Text(
                          DateUtilsHelper.getMonthName(i + 1),
                          style: Theme.of(context).textTheme.bodyLarge,
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
                    selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(),
                    onSelectedItemChanged: (i) =>
                        selectedYear = MonthYearPicker._startYear + i,
                    children: List.generate(
                      MonthYearPicker._yearCount,
                      (i) => Center(
                        child: Text(
                          "${MonthYearPicker._startYear + i}",
                          style: Theme.of(context).textTheme.bodyLarge,
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
