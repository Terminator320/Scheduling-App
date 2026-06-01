import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class DetailsSectionRow extends StatelessWidget {
  const DetailsSectionRow({
    required this.label,
    required this.value,
    this.subtitle,
    this.customValue,
    super.key,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Widget? customValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        customValue ??
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class DetailsAddressRow extends StatelessWidget {
  const DetailsAddressRow({
    required this.label,
    required this.address,
    this.onTap,
    super.key,
  });

  final String label;
  final String address;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.r8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      address,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Text(
            address,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
      ],
    );
  }
}

class DetailsEmployeePill extends StatelessWidget {
  const DetailsEmployeePill({required this.employee, super.key});

  final EmployeeRecord employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r8 + 2),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: employee.color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                employee.initials,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color:
                      ThemeData.estimateBrightnessForColor(employee.color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (employee.email.isNotEmpty)
                  Text(
                    employee.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
