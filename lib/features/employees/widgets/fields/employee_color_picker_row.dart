import 'package:flutter/material.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/features/employees/widgets/fields/employee_color_grid.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

class EmployeeColorPickerRow extends StatelessWidget {
  const EmployeeColorPickerRow({
    required this.selectedColor,
    required this.onColorChanged,
    super.key,
    this.required = false,
    this.usedColors = const {},
  });

  final int selectedColor;
  final ValueChanged<int> onColorChanged;
  final bool required;
  final Set<int> usedColors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formLabel(
          context,
          context.l10n.employees_employeeColor,
          required: required,
        ),
        EmployeeColorGrid(
          selectedColor: selectedColor,
          onColorSelected: onColorChanged,
          usedColors: usedColors,
        ),
      ],
    );
  }
}
