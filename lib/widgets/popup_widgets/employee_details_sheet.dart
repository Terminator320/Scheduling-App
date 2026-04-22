import 'package:flutter/material.dart';

import '../../models/employee_record.dart';
import '../../services/user_service.dart';
import '../../utils/app_text.dart';
import '../sheet_widgets.dart';


class EmployeeDetailsSheet extends StatelessWidget {
  const EmployeeDetailsSheet({super.key, required this.employee});

  final EmployeeRecord employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 18),
          Center(
            child: Text(
              tr(context, 'Employee details'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _DetailField(label: tr(context, 'Name'), value: employee.name),
          const SizedBox(height: 12),
          _DetailField(label: tr(context, 'Email'), value: employee.email),
          const SizedBox(height: 12),
          _DetailField(
            label: tr(context, 'Phone number'),
            value: employee.phone.isEmpty ? '-' : employee.phone,
          ),
          const SizedBox(height: 12),
          _DetailField(label: tr(context, 'Role'), value: employee.role),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: employee.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(tr(context, 'Employee color')),
            ],
          ),
        ],
      ),
    );
  }

}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withAlpha(170),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '-' : value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
