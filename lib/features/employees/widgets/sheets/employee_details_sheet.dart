import 'package:flutter/material.dart';

import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/views/employee_details_view.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EmployeeDetailsSheet extends StatelessWidget {
  const EmployeeDetailsSheet({
    required this.employee,
    required this.isCurrentUserAdmin,
    super.key,
  });

  final EmployeeRecord employee;
  final bool isCurrentUserAdmin;

  @override
  Widget build(BuildContext context) {
    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return EmployeeDetailsView(
          employee: employee,
          isCurrentUserAdmin: isCurrentUserAdmin,
          scrollController: scrollController,
          showHandle: true,
          onEdit: () => Navigator.pop(sheetContext, 'edit'),
        );
      },
    );
  }
}
