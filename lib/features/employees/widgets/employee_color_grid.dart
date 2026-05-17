import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

class EmployeeColorGrid extends ConsumerWidget {
  const EmployeeColorGrid({
    required this.selectedColor,
    required this.onColorSelected,
    super.key,
    this.usedColors = const {},
  });

  final int selectedColor;
  final ValueChanged<int> onColorSelected;
  final Set<int> usedColors;

  static final _quickPicks = AppColors.employeePalette.take(8).toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCustomColor = !_quickPicks.any(
      (c) => c.toARGB32() == selectedColor,
    );

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ..._quickPicks.map((color) {
          final colorInt = color.toARGB32();
          final isUsed = usedColors.contains(colorInt);
          return _SwatchButton(
            color: color,
            isSelected: colorInt == selectedColor,
            isDisabled: isUsed,
            onTap: isUsed ? null : () => onColorSelected(colorInt),
          );
        }),
        if (isCustomColor)
          _SwatchButton(
            color: Color(selectedColor),
            isSelected: true,
            onTap: null,
          ),
        GestureDetector(
          onTap: () => _openCustomPicker(context, ref),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.add,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openCustomPicker(BuildContext context, WidgetRef ref) async {
    final picked = await showColorPickerDialog(
      context,
      Color(selectedColor),
      spacing: 0,
      runSpacing: 0,
      borderRadius: 4,
      wheelDiameter: 165,
      showColorCode: true,
      colorCodeHasColor: true,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.wheel: true,
        ColorPickerType.accent: false,
        ColorPickerType.primary: false,
      },
      actionButtons: const ColorPickerActionButtons(
        okButton: true,
        closeButton: true,
        dialogActionButtons: false,
      ),
      constraints: const BoxConstraints(
        minHeight: 480,
        minWidth: 300,
        maxWidth: 320,
      ),
    );
    if (!context.mounted) return;
    if (usedColors.contains(picked.toARGB32())) {
      ref.read(noticeServiceProvider).error(context.l10n.colorAlreadyUsed);
      return;
    }
    onColorSelected(picked.toARGB32());
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.3 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDuration.fast,
          curve: Curves.easeOut,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2.5,
                  )
                : Border.all(color: Colors.transparent, width: 2.5),
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  color:
                      ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  size: 16,
                )
              : null,
        ),
      ),
    );
  }
}
