import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

class MonthYearPicker {
  // Year wheel spans a sliding window relative to today so the range never
  // needs a manual code bump: a few years back through several years ahead.
  static const int _pastYears = 5;
  static const int _futureYears = 15;

  static Future<DateTime?> show(
    BuildContext context,
    DateTime focusedDay,
  ) async {
    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      sheetAnimationStyle: AppMotion.sheetStyle,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.r20),
        ),
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
  late final int _startYear;
  late final int _yearCount;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _yearController;

  @override
  void initState() {
    super.initState();
    _startYear = DateTime.now().year - MonthYearPicker._pastYears;
    _yearCount = MonthYearPicker._pastYears + MonthYearPicker._futureYears + 1;
    selectedMonth = widget.focusedDay.month;
    selectedYear = widget.focusedDay.year;
    _monthController = FixedExtentScrollController(
      initialItem: selectedMonth - 1,
    );
    _yearController = FixedExtentScrollController(
      initialItem: (selectedYear - _startYear).clamp(0, _yearCount - 1),
    );
  }

  @override
  void dispose() {
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyLarge = theme.textTheme.bodyLarge;
    final monthFormat = DateFormat.MMMM(locale);

    // Sized past the bottom view padding + SafeArea so the wheels don't sit
    // under the home indicator.
    return SizedBox(
      height: 300 + MediaQuery.viewPaddingOf(context).bottom,
      child: SafeArea(
        top: false,
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
                      context.l10n.common_cancel,
                      style: TextStyle(color: scheme.primary),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text(
                      context.l10n.common_done,
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
                      scrollController: _monthController,
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
                      scrollController: _yearController,
                      itemExtent: 40,
                      useMagnifier: true,
                      magnification: 1.2,
                      squeeze: 1.2,
                      onSelectedItemChanged: (i) =>
                          selectedYear = _startYear + i,
                      children: List.generate(
                        _yearCount,
                        (i) => Center(
                          child: Text(
                            '${_startYear + i}',
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
      ),
    );
  }
}
