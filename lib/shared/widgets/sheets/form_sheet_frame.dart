import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Form-sheet chrome from `06-sheets-and-dialogs.md`: a fixed-height sheet with
/// a white bar carrying **Cancel · title · primary verb** and no grabber.
///
/// Fixed height rather than draggable is the design's own call — the bar is the
/// dismiss affordance, and a form that resizes under the keyboard loses the
/// user's place. The scrim still dismisses on tap.
///
/// `FormSheetScaffold` is untouched: the client and employee sheets keep it
/// until P3/P4 migrate them.
class FormSheetFrame extends StatelessWidget {
  const FormSheetFrame({
    required this.title,
    required this.primaryLabel,
    required this.children,
    super.key,
    this.onPrimary,
    this.onCancel,
    this.isBusy = false,
    this.heightFactor = 0.92,
  });

  final String title;
  final String primaryLabel;
  final List<Widget> children;

  /// Null disables the primary verb.
  final VoidCallback? onPrimary;

  /// Defaults to popping the sheet.
  final VoidCallback? onCancel;
  final bool isBusy;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: heightFactor,
      minChildSize: heightFactor,
      maxChildSize: heightFactor,
      expand: false,
      builder: (sheetContext, scrollController) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(sheetContext).unfocus(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.rSheet),
            ),
            boxShadow: theme.cardStyle.sheetShadow,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.rSheet),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  _SheetBar(
                    title: title,
                    primaryLabel: primaryLabel,
                    onPrimary: isBusy ? null : onPrimary,
                    onCancel: isBusy
                        ? null
                        : (onCancel ?? () => Navigator.maybePop(sheetContext)),
                    isBusy: isBusy,
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        left: 18,
                        right: 18,
                        top: AppSpacing.sp16,
                        // Keyboard-inset aware, so the focused field is never
                        // hidden behind the keyboard.
                        bottom:
                            MediaQuery.viewInsetsOf(sheetContext).bottom + 30,
                      ),
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetBar extends StatelessWidget {
  const _SheetBar({
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onCancel,
    required this.isBusy,
  });

  final String title;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp8),
        child: Row(
          children: [
            TextButton(
              onPressed: onCancel,
              child: Text(
                context.l10n.common_cancel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.palette.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: onPrimary,
              child: isBusy
                  ? const AdaptiveProgressIndicator(size: 18)
                  : Text(
                      primaryLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onPrimary == null
                            ? theme.palette.textMuted
                            : theme.palette.primaryAccent,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
