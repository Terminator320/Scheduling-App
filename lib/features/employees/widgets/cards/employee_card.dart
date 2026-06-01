import 'package:flutter/material.dart';

import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/cards/list_item_tile.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

class EmployeeCard extends StatelessWidget {
  const EmployeeCard({
    required this.employee,
    required this.onTap,
    super.key,
    this.selected = false,
  });

  final EmployeeRecord employee;
  final VoidCallback onTap;
  final bool selected;

  AppointmentStatus get _status => employee.isActive
      ? AppointmentStatus.active
      : employee.isDisabled
      ? AppointmentStatus.disabled
      : AppointmentStatus.invited;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // ListItemTile's InkWell already exposes button semantics and reads the
    // visible name, email, and status chip; no explicit Semantics label needed.
    return ListItemTile(
      avatarName: employee.name.isEmpty ? '?' : employee.name,
      avatarColor: employee.isDisabled ? scheme.outlineVariant : employee.color,
      title: employee.name.isEmpty ? '—' : employee.name,
      subtitle: employee.email,
      selected: selected,
      dimmed: employee.isDisabled,
      trailing: StatusChip(status: _status),
      onTap: onTap,
    );
  }
}
