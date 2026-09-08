import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/views/employee_details_view.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EmployeeDetailsSheet extends ConsumerWidget {
  const EmployeeDetailsSheet({
    required this.employee,
    required this.isCurrentUserAdmin,
    super.key,
  });

  final EmployeeRecord employee;
  final bool isCurrentUserAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveUsers = ref.watch(allUsersStreamProvider).asData?.value;
    EmployeeRecord? liveEmployee;
    if (liveUsers != null) {
      for (final candidate in liveUsers) {
        if (candidate.id == employee.id) {
          liveEmployee = candidate;
          break;
        }
      }
    }
    if (liveUsers != null && liveEmployee == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final current = liveEmployee ?? employee;

    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return EmployeeDetailsView(
          employee: current,
          isCurrentUserAdmin: isCurrentUserAdmin,
          scrollController: scrollController,
          showHandle: true,
          onEdit: () => Navigator.pop(sheetContext, 'edit'),
        );
      },
    );
  }
}
