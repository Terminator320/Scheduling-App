import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

class MonthYearPicker {
  // The year wheel spans a window relative to today, so it never needs manual bumping as time passes.
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
    final theme = Theme.of(context);

    // Size past the bottom view padding so the wheels don't sit under the home indicator.
    return SizedBox(
      height: 300 + MediaQuery.viewPaddingOf(context).bottom,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _actionBar(context, theme.colorScheme),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _monthWheel(context, theme)),
                  Expanded(child: _yearWheel(theme)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cancel / Done, the iOS wheel-picker convention: the sheet commits on Done
  /// rather than on every wheel movement, so a scroll past the target is not a
  /// selection.
  Widget _actionBar(BuildContext context, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sp16,
      vertical: AppSpacing.sp8,
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.l10n.common_cancel,
            style: TextStyle(color: scheme.primary),
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () =>
              Navigator.pop(context, DateTime(selectedYear, selectedMonth)),
          child: Text(
            context.l10n.common_done,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _monthWheel(BuildContext context, ThemeData theme) {
    // Built once for the whole wheel, never per item — constructing a
    // `DateFormat` verifies the locale and parses a skeleton, and this builder
    // runs for all twelve.
    final monthFormat = DateFormat.MMMM(
      Localizations.localeOf(context).toString(),
    );
    return _wheel(
      controller: _monthController,
      itemCount: 12,
      onSelected: (i) => selectedMonth = i + 1,
      labelAt: (i) => monthFormat.format(DateTime(0, i + 1)),
      theme: theme,
    );
  }

  Widget _yearWheel(ThemeData theme) => _wheel(
    controller: _yearController,
    itemCount: _yearCount,
    onSelected: (i) => selectedYear = _startYear + i,
    labelAt: (i) => '${_startYear + i}',
    theme: theme,
  );

  /// The two wheels' shared geometry — one spelling so they cannot drift out
  /// of alignment with each other.
  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required ValueChanged<int> onSelected,
    required String Function(int) labelAt,
    required ThemeData theme,
  }) => CupertinoPicker(
    scrollController: controller,
    itemExtent: 40,
    useMagnifier: true,
    magnification: 1.2,
    squeeze: 1.2,
    onSelectedItemChanged: onSelected,
    children: List.generate(
      itemCount,
      (i) => Center(
        child: Text(labelAt(i), style: theme.textTheme.bodyLarge),
      ),
    ),
  );
}
