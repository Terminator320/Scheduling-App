import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The one sheet header: **Cancel · title · primary verb**, on a surface bar
/// with a hairline bottom border.
///
/// Every add/edit sheet in the app renders this — appointments, clients and
/// people — so the dismiss affordance, the title and the commit verb sit in
/// the same place on every form. `FormSheetFrame` composes it; use it directly
/// only for a sheet that needs different chrome around the same bar.
///
/// Layout notes, both load-bearing:
///
/// * The three slots are `Expanded`, not `Flexible`. Loose fit let the middle
///   `Text` shrink to its intrinsic width (the two `Align`s expand, a bare
///   `Text` does not), so the leftover main-axis space pooled at the trailing
///   edge and the title rendered left of centre with the verb floating
///   mid-bar. Tight fit pins each slot to its share.
/// * Every slot is still flexible, so the bar cannot overflow: three intrinsic
///   widths exceed a 260px viewport once text is scaled up, and a non-flex
///   button would have nothing to give. The side slots share a flex so the
///   title stays optically centred between them.
class SheetHeaderBar extends StatelessWidget {
  const SheetHeaderBar({
    required this.title,
    required this.primaryLabel,
    super.key,
    this.onPrimary,
    this.onCancel,
    this.isBusy = false,
  });

  final String title;

  /// The commit verb — "Save", "Add", "Send invite".
  final String primaryLabel;

  /// Null renders the verb disabled.
  final VoidCallback? onPrimary;

  /// Null renders Cancel disabled; supply the dismiss action explicitly.
  final VoidCallback? onCancel;

  /// Swaps the verb for a spinner and blocks both actions, so an in-flight
  /// save can't be double-submitted from the bar.
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
            Expanded(
              flex: 3,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: isBusy ? null : onCancel,
                  child: Text(
                    context.l10n.common_cancel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.palette.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: isBusy ? null : onPrimary,
                  child: isBusy
                      ? const AdaptiveProgressIndicator(size: 18)
                      : Text(
                          primaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: onPrimary == null
                                ? theme.palette.textMuted
                                : theme.palette.primaryAccent,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
