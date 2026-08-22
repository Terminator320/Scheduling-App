import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

class EmployeePicker extends StatelessWidget {
  const EmployeePicker({
    required this.allEmployees,
    required this.selectedEmployees,
    super.key,
    this.selectable = true,
    this.hasError = false,
    this.errorText,
    this.onToggle,
  });

  final List<EmployeeRecord> allEmployees;
  final List<EmployeeRecord> selectedEmployees;
  final bool selectable;
  final bool hasError;

  /// When this is non-null, an error row is rendered below the chips and their borders get highlighted.
  final String? errorText;
  final void Function(EmployeeRecord)? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = this.hasError || errorText != null;
    // In read-only mode the picker is a summary of who is ON the job, so the
    // unselected staff are not rendered at all.
    final displayEmployees = selectable
        ? allEmployees
        : allEmployees
              .where((e) => selectedEmployees.any((s) => s.id == e.id))
              .toList();

    final content = displayEmployees.isEmpty
        ? Text(
            selectable
                ? context.l10n.common_noEmployeesFound
                : context.l10n.calendar_noEmployeesAssigned,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          )
        : Wrap(
            spacing: AppSpacing.sp8,
            runSpacing: AppSpacing.sp8,
            children: [
              for (final employee in displayEmployees)
                _EmployeeChip(
                  employee: employee,
                  isSelected: selectedEmployees.any((e) => e.id == employee.id),
                  selectable: selectable,
                  hasError: hasError,
                  onTap: selectable ? () => onToggle?.call(employee) : null,
                ),
            ],
          );

    if (errorText == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        content,
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.sp4,
            left: AppSpacing.sp4,
          ),
          child: Text(
            errorText!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ),
      ],
    );
  }
}

/// One staff chip. Its own widget so a row rebuilds on its own rather than as
/// part of a 60-line closure body re-evaluated per employee.
class _EmployeeChip extends StatelessWidget {
  const _EmployeeChip({
    required this.employee,
    required this.isSelected,
    required this.selectable,
    required this.hasError,
    required this.onTap,
  });

  final EmployeeRecord employee;
  final bool isSelected;
  final bool selectable;
  final bool hasError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: selectable,
      selected: isSelected,
      label: employee.name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sp8,
            AppSpacing.sp4,
            AppSpacing.sp12,
            AppSpacing.sp4,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            border: Border.all(
              // An unselected chip carries the error outline, since "pick
              // someone" is what the error is asking for.
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
              AppAvatar(
                name: employee.name,
                color: employee.color,
                size: AvatarSize.xs,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Flexible(
                child: Text(
                  employee.name.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
