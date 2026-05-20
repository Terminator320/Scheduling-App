import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class EmployeePicker extends StatelessWidget {
  const EmployeePicker({
    required this.allEmployees,
    required this.selectedEmployees,
    super.key,
    this.selectable = true,
    this.hasError = false,
    this.onToggle,
  });
  final List<EmployeeRecord> allEmployees;
  final List<EmployeeRecord> selectedEmployees;
  final bool selectable;
  final bool hasError;
  final void Function(EmployeeRecord)? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayEmployees = selectable
        ? allEmployees
        : allEmployees
              .where((e) => selectedEmployees.any((s) => s.id == e.id))
              .toList();

    if (displayEmployees.isEmpty) {
      return Text(
        selectable
            ? context.l10n.common_noEmployeesFound
            : context.l10n.calendar_noEmployeesAssigned,
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      );
    }

    return Wrap(
      spacing: AppSpacing.sp8,
      runSpacing: AppSpacing.sp8,
      children: displayEmployees.map((employee) {
        final isSelected = selectedEmployees.any((e) => e.id == employee.id);

        return GestureDetector(
          onTap: selectable ? () => onToggle?.call(employee) : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              border: Border.all(
                color: hasError && !isSelected
                    ? scheme.error
                    : isSelected
                    ? scheme.primary
                    : scheme.outlineVariant,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(AppRadius.rFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: employee.color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      employee.initials,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color:
                            ThemeData.estimateBrightnessForColor(
                                  employee.color,
                                ) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  employee.name.split(' ').first,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
