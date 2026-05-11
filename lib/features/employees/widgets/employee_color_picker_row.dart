import 'package:flutter/material.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/widgets/employee_color_grid.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

/// Color selector row: quick-pick swatches + custom color wheel button.
class EmployeeColorPickerRow extends StatelessWidget {
  const EmployeeColorPickerRow({
    required this.selectedColor, required this.onColorChanged, super.key,
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
        formLabel(context, context.l10n.employeeColor, required: required),
        EmployeeColorGrid(
          selectedColor: selectedColor,
          onColorSelected: onColorChanged,
          usedColors: usedColors,
        ),
      ],
    );
  }
}
