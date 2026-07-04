import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';

class AppSearchBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSearchBar({
    super.key,
    this.onChanged,
    this.hintText,
    this.controller,
    this.focusNode,
    this.textScaler = TextScaler.noScaling,
  });

  /// Vertical margins around the field — fixed chrome that doesn't grow with
  /// the user's text size.
  static const double _verticalMargins = AppSpacing.sp8 * 2;

  /// The field itself (text + content padding + border) at text scale 1.0.
  static const double _fieldHeight = 44;

  static const double preferredHeight = _verticalMargins + _fieldHeight;

  final ValueChanged<String>? onChanged;

  /// Placeholder shown in the field; defaults to the localized generic
  /// "Search..." when null.
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Pass `MediaQuery.textScalerOf(context)` from the call site so the
  /// app-bar bottom slot reserves enough height at large text sizes instead
  /// of clipping the field ([preferredSize] has no BuildContext to read the
  /// scale itself).
  final TextScaler textScaler;

  @override
  Size get preferredSize =>
      Size.fromHeight(_verticalMargins + textScaler.scale(_fieldHeight));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp8,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged ?? (_) {},
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: hintText ?? context.l10n.common_search,
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sp12),
          suffixIcon: controller != null
              ? ClearTextButton(
                  controller: controller!,
                  onCleared: () => onChanged?.call(''),
                )
              : null,
        ),
      ),
    );
  }
}
