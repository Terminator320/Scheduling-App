import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/policies/team_row_policy.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/list_item_tile.dart';
import 'package:scheduling/shared/widgets/feedback/user_status_chip.dart';

class EmployeeCard extends ConsumerWidget {
  const EmployeeCard({
    required this.employee,
    required this.onTap,
    super.key,
    this.selected = false,
  });

  final EmployeeRecord employee;
  final VoidCallback onTap;
  final bool selected;

  UserStatus get _status => UserStatus.fromRaw(employee.status);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // One shared day-range listener behind this — not a query per row.
    final jobsToday = ref.watch(employeeJobsTodayProvider)[employee.id] ?? 0;

    // ListItemTile's InkWell already exposes button semantics, so we don't
    // need an explicit Semantics label here.
    return ListItemTile(
      avatarName: employee.name.isEmpty ? '?' : employee.name,
      avatarColor: employee.isDisabled ? scheme.outlineVariant : employee.color,
      title: employee.name.isEmpty ? '—' : employee.name,
      subtitle: teamRowSubtitle(
        l10n: context.l10n,
        jobTitle: employee.jobTitle,
        jobsToday: jobsToday,
        email: employee.email,
      ),
      selected: selected,
      dimmed: employee.isDisabled,
      trailing: UserStatusChip(status: _status),
      onTap: onTap,
    );
  }
}
