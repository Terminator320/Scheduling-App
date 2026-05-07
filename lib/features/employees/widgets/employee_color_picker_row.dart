import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'employee_color_grid.dart';

/// Color selector row: quick-pick swatches + custom color wheel button.
class EmployeeColorPickerRow extends StatelessWidget {
  const EmployeeColorPickerRow({
    super.key,
    required this.selectedColor,
    required this.onColorChanged,
  });

  final int selectedColor;
  final ValueChanged<int> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.employeeColor,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.sp12),
        EmployeeColorGrid(
          selectedColor: selectedColor,
          onColorSelected: onColorChanged,
        ),
      ],
    );
  }
}
