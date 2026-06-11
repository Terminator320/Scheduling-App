import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Tap-friendly grid of the employee palette. Colors already used by another
/// employee are hidden entirely, so everything shown is pickable: 48px-target
/// swatches with ripple feedback, plus a trailing rainbow swatch that opens
/// the custom picker (a tappable palette first; the wheel one tab away).
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

  void _pick(int colorInt) {
    HapticFeedback.selectionClick();
    onColorSelected(colorInt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only offer colors no other employee has — the selected color always
    // stays visible so the current choice can't vanish from its own form.
    final available = [
      for (final color in AppColors.employeePalette)
        if (!usedColors.contains(color.toARGB32()) ||
            color.toARGB32() == selectedColor)
          color,
    ];
    final isCustomColor = !available.any(
      (c) => c.toARGB32() == selectedColor,
    );

    return Wrap(
      spacing: AppSpacing.sp4,
      runSpacing: AppSpacing.sp4,
      children: [
        for (var i = 0; i < available.length; i++)
          _SwatchButton(
            color: available[i],
            isSelected: available[i].toARGB32() == selectedColor,
            semanticLabel: context.l10n.employees_colorOption(i + 1),
            onTap: () => _pick(available[i].toARGB32()),
          ),
        if (isCustomColor)
          _SwatchButton(
            color: Color(selectedColor),
            isSelected: true,
            semanticLabel: context.l10n.employees_customColor,
            onTap: null,
          ),
        _CustomColorButton(onTap: () => _openCustomPicker(context, ref)),
      ],
    );
  }

  Future<void> _openCustomPicker(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final picked = await showColorPickerDialog(
      context,
      Color(selectedColor),
      title: Text(
        l10n.employees_customColor,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      // Tap-a-swatch palette with shade rows — every interaction is a tap.
      // No wheel (finger-dragging precision) and no hex-code field.
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
        ColorPickerType.wheel: false,
      },
      borderRadius: 20,
      actionButtons: const ColorPickerActionButtons(
        okButton: true,
        closeButton: true,
        dialogActionButtons: false,
      ),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 320),
    );
    if (!context.mounted) return;
    final pickedInt = picked.toARGB32();
    // A custom pick can still collide with another employee's custom color.
    if (usedColors.contains(pickedInt)) {
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_colorAlreadyUsed);
      return;
    }
    if (pickedInt != selectedColor) _pick(pickedInt);
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.color,
    required this.isSelected,
    required this.semanticLabel,
    required this.onTap,
  });

  static const double _targetSize = 48;
  static const double _swatchSize = 38;

  final Color color;
  final bool isSelected;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      child: InkResponse(
        onTap: onTap,
        radius: _targetSize / 2,
        child: SizedBox(
          width: _targetSize,
          height: _targetSize,
          child: Center(
            child: AnimatedContainer(
              duration: AppDuration.fast,
              curve: Curves.easeOut,
              width: _swatchSize,
              height: _swatchSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? scheme.onSurface : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      color: contrastingForegroundFor(color),
                      size: 18,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The "more colors" affordance: a rainbow-ringed swatch that reads as
/// "any color", sized and rippled like the palette swatches.
class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = context.l10n.employees_customColor;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Color(0xFFEF4444), // red
                      Color(0xFFF59E0B), // amber
                      Color(0xFF10B981), // emerald
                      Color(0xFF06B6D4), // cyan
                      Color(0xFF6366F1), // indigo
                      Color(0xFFEC4899), // pink
                      Color(0xFFEF4444), // back to red for a seamless ring
                    ],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surface,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
