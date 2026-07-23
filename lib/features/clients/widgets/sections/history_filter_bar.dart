import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// An assignable employee surfaced as a history filter option.
typedef HistoryEmployeeOption = ({String id, String name});

/// Horizontally scrollable row of dropdown filter chips (year, employee); chips hide when no options.
class HistoryFilterBar extends StatelessWidget {
  const HistoryFilterBar({
    required this.years,
    required this.selectedYear,
    required this.onYearChanged,
    required this.employees,
    required this.selectedEmployeeId,
    required this.onEmployeeChanged,
    required this.allYearsLabel,
    required this.allStaffLabel,
    super.key,
  });

  final List<int> years;
  final int? selectedYear;
  final ValueChanged<int?> onYearChanged;

  final List<HistoryEmployeeOption> employees;
  final String? selectedEmployeeId;
  final ValueChanged<String?> onEmployeeChanged;

  final String allYearsLabel;
  final String allStaffLabel;

  /// True if bar renders at least one chip (lets caller skip padding when no filters).
  static bool hasFilters({
    required List<int> years,
    required List<HistoryEmployeeOption> employees,
  }) => years.length > 1 || employees.length > 1;

  @override
  Widget build(BuildContext context) {
    final showYear = years.length > 1;
    final showEmployee = employees.length > 1;
    if (!showYear && !showEmployee) return const SizedBox.shrink();

    var selectedName = allStaffLabel;
    if (selectedEmployeeId != null) {
      for (final e in employees) {
        if (e.id == selectedEmployeeId) {
          selectedName = e.name;
          break;
        }
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
      child: Row(
        children: [
          if (showYear)
            _DropdownFilterChip(
              label: selectedYear?.toString() ?? allYearsLabel,
              isActive: selectedYear != null,
              options: [
                _FilterOption(allYearsLabel, () => onYearChanged(null)),
                for (final y in years)
                  _FilterOption('$y', () => onYearChanged(y)),
              ],
            ),
          if (showYear && showEmployee) const SizedBox(width: AppSpacing.sp8),
          if (showEmployee)
            _DropdownFilterChip(
              label: selectedName,
              isActive: selectedEmployeeId != null,
              icon: Icons.person_outline_rounded,
              options: [
                _FilterOption(allStaffLabel, () => onEmployeeChanged(null)),
                for (final e in employees)
                  _FilterOption(e.name, () => onEmployeeChanged(e.id)),
              ],
            ),
        ],
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption(this.label, this.onSelected);
  final String label;
  final VoidCallback onSelected;
}

/// FilterChip that opens MenuAnchor of choices; highlights when non-default value chosen.
class _DropdownFilterChip extends StatelessWidget {
  const _DropdownFilterChip({
    required this.label,
    required this.isActive,
    required this.options,
    this.icon,
  });

  final String label;
  final bool isActive;
  final List<_FilterOption> options;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            onPressed: option.onSelected,
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => FilterChip(
        avatar: icon == null ? null : Icon(icon, size: 18),
        showCheckmark: false,
        selected: isActive,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
        onSelected: (_) =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
