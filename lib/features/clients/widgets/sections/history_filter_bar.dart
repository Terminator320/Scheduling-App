import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/history_grouping.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// An assignable employee surfaced as a history filter option.
typedef HistoryEmployeeOption = ({String id, String name});

/// The History filter row: the two quick-filter status chips, then the year and
/// crew selects.
///
/// The selects open a single-select **sheet** — on iOS a `CupertinoActionSheet`
/// — rather than the `MenuAnchor` they used to. The year and crew chips hide
/// themselves when there is nothing to choose between; the status chips do not,
/// because `done` and `cancelled` are what History holds by definition.
class HistoryFilterBar extends StatelessWidget {
  const HistoryFilterBar({
    required this.years,
    required this.selectedYear,
    required this.onYearChanged,
    required this.employees,
    required this.selectedEmployeeId,
    required this.onEmployeeChanged,
    required this.selectedStatus,
    required this.onStatusChanged,
    super.key,
  });

  final List<int> years;
  final int? selectedYear;
  final ValueChanged<int?> onYearChanged;

  final List<HistoryEmployeeOption> employees;
  final String? selectedEmployeeId;
  final ValueChanged<String?> onEmployeeChanged;

  /// Null means both statuses — tapping the selected chip clears it. Modelled
  /// as one nullable value rather than two independent toggles so "neither
  /// selected" and "both selected" cannot be two spellings of the same list.
  final HistoryStatusFilter? selectedStatus;
  final ValueChanged<HistoryStatusFilter?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showYear = years.length > 1;
    final showEmployee = employees.length > 1;

    var selectedName = l10n.clients_allStaff;
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
        spacing: AppSpacing.sp8,
        children: [
          for (final status in HistoryStatusFilter.values)
            _StatusFilterChip(
              // The app's existing status wording, not a second vocabulary:
              // the chip reads exactly what the StatusChip on the card beside
              // it reads.
              label: statusLabel(l10n, _statusOf(status)),
              selected: selectedStatus == status,
              onSelected: (on) => onStatusChanged(on ? status : null),
            ),
          if (showYear)
            _SheetFilterChip(
              label: selectedYear?.toString() ?? l10n.clients_allYears,
              isActive: selectedYear != null,
              title: l10n.clients_historyFilterYear,
              options: [
                _FilterOption(l10n.clients_allYears, () => onYearChanged(null)),
                for (final y in years)
                  _FilterOption('$y', () => onYearChanged(y)),
              ],
            ),
          if (showEmployee)
            _SheetFilterChip(
              label: selectedName,
              isActive: selectedEmployeeId != null,
              icon: Icons.person_outline_rounded,
              title: l10n.clients_historyFilterStaff,
              options: [
                _FilterOption(
                  l10n.clients_allStaff,
                  () => onEmployeeChanged(null),
                ),
                for (final e in employees)
                  _FilterOption(e.name, () => onEmployeeChanged(e.id)),
              ],
            ),
        ],
      ),
    );
  }

  static AppointmentStatus _statusOf(HistoryStatusFilter filter) =>
      switch (filter) {
        HistoryStatusFilter.complete => AppointmentStatus.done,
        HistoryStatusFilter.cancelled => AppointmentStatus.cancelled,
      };
}

class _FilterOption {
  const _FilterOption(this.label, this.onSelected);
  final String label;
  final VoidCallback onSelected;
}

/// One of the two quick filters. A plain toggle — its own `selected` state is
/// the only thing it carries, so the caller owns the "tapping the selected one
/// clears it" rule.
class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: onSelected,
  );
}

/// A chip that opens a single-select sheet of choices, highlighted whenever a
/// non-default value is chosen.
class _SheetFilterChip extends StatelessWidget {
  const _SheetFilterChip({
    required this.label,
    required this.isActive,
    required this.title,
    required this.options,
    this.icon,
  });

  final String label;
  final bool isActive;
  final String title;
  final List<_FilterOption> options;
  final IconData? icon;

  /// Options are chosen by INDEX, not by their value: the "All years" row
  /// selects null, and `showAdaptiveActionSheet` already returns null for a
  /// dismissal. An index keeps the two apart.
  Future<void> _pick(BuildContext context) async {
    final chosen = await showAdaptiveActionSheet<int>(
      context,
      title: title,
      actions: [
        for (var i = 0; i < options.length; i++)
          AdaptiveSheetAction(value: i, label: options[i].label),
      ],
    );
    if (chosen == null || !context.mounted) return;
    options[chosen].onSelected();
  }

  @override
  Widget build(BuildContext context) => FilterChip(
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
    onSelected: (_) => _pick(context),
  );
}
