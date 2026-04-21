import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

import '../../utils/app_text.dart';

/// Single-row color selector: tapping the indicator opens
/// the full flex_color_picker dialog (primary palette + wheel).
class EmployeeColorPickerRow extends StatelessWidget {
  const EmployeeColorPickerRow({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final Color selected;
  final ValueChanged<Color> onSelect;

  Future<void> _openDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final picked = await showColorPickerDialog(
      context,
      selected,
      title: Text(
        tr(context, 'Employee Color'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      width: 36,
      height: 36,
      borderRadius: 18,
      spacing: 6,
      runSpacing: 6,
      enableShadesSelection: false,
      wheelDiameter: 180,
      pickersEnabled: const {
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
        ColorPickerType.wheel: true,
      },
      actionButtons: const ColorPickerActionButtons(
        okButton: true,
        closeButton: true,
        dialogActionButtons: false,
      ),
      constraints: const BoxConstraints(
        minHeight: 220,
        minWidth: 320,
        maxWidth: 340,
      ),
    );
    onSelect(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        ColorIndicator(
          width: 40,
          height: 40,
          borderRadius: 20,
          color: selected,
          hasBorder: true,
          borderColor: theme.colorScheme.outlineVariant,
          onSelectFocus: false,
          onSelect: () => _openDialog(context),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr(context, 'Tap to change color'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(170),
            ),
          ),
        ),
      ],
    );
  }
}
