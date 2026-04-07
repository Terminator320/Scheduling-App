import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/date_utils_helper.dart';

class MonthYearPicker {
  static const int _startYear = 2000;
  static const int _yearCount = 30;

  static Future<DateTime?> show(
      BuildContext context,
      DateTime focusedDay,
      ) async {
    return await showModalBottomSheet<DateTime>(
      context: context,
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.35,
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel"),
              ),
              Text("Select Date"),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  DateTime(selectedYear, selectedMonth),
                ),
                child: Text("Done"),
              ),
            ],
          ),
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
                    selectionOverlay: Container(
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    onSelectedItemChanged: (i) => selectedMonth = i + 1,
                    children: List.generate(
                      12,
                          (i) => Center(
                        child: Text(DateUtilsHelper.getMonthName(i + 1)),
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
                    onSelectedItemChanged: (i) =>
                    selectedYear = MonthYearPicker._startYear + i,
                    children: List.generate(
                      MonthYearPicker._yearCount,
                          (i) => Center(
                        child: Text("${MonthYearPicker._startYear + i}"),
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
