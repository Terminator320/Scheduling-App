import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/l10n/l10n.dart';

/// How wide the active chip's label may grow before it ellipsizes. An
/// unbounded street ("1200 Rue Sherbrooke Ouest") would otherwise push the
/// Filter button off the row.
const double _maxChipLabelWidth = 160;

/// The Filter button, pinned FIRST and outside any scroller, plus the one chip
/// naming whatever filter is active.
///
/// Pinned because the row it replaces was a 48px horizontal scroller holding
/// five controls, so at large text scale something was always off-screen on
/// arrival. Only ONE chip can ever show: [ClientsFilter] is a sealed one-of.
class ClientsFilterBar extends StatelessWidget {
  const ClientsFilterBar({
    required this.selected,
    required this.onOpen,
    required this.onClear,
    this.activeBuildingLabel,
    super.key,
  });

  final ClientsFilter selected;
  final VoidCallback onOpen;
  /// Clears the active filter. Picking one is the sheet's job.
  final VoidCallback onClear;

  /// Street of the active [ClientsFilterBuilding], remembered by the caller
  /// when it was picked — this bar never watches the building scan.
  final String? activeBuildingLabel;

  String? _activeLabel(AppLocalizations l10n) => switch (selected) {
    ClientsFilterAll() => null,
    ClientsFilterType(:final type) => clientTypeLabel(l10n, type),
    ClientsFilterArchived() => l10n.clients_filterArchived,
    ClientsFilterBuilding() =>
      activeBuildingLabel ?? l10n.clients_filterByAddress,
  };

  /// The dot rides INSIDE the label rather than in a `Badge`: Badge stacks,
  /// and a Stack cannot lay out the unbounded width a Row hands a non-flex
  /// child.
  Widget _button(BuildContext context, AppLocalizations l10n, bool isActive) =>
      OutlinedButton.icon(
        // The app theme makes every OutlinedButton full-width
        // (minimumSize: Size(infinity, 48)), which is right for a stacked
        // action bar and wrong for a control sitting in a row. Width hugs the
        // label; the 48px tap height stays.
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: onOpen,
        icon: const Icon(Icons.tune, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.clients_filter),
            if (isActive) ...[
              const SizedBox(width: AppSpacing.sp4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Theme.of(context).palette.primaryAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      );

  Widget _chip(AppLocalizations l10n, String label) => InputChip(
    label: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxChipLabelWidth),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    deleteIcon: const Icon(Icons.close, size: 18),
    deleteButtonTooltipMessage: l10n.clients_clearFilter,
    onDeleted: onClear,
    onPressed: onOpen,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = _activeLabel(l10n);

    // The button is the one control that must never be pushed off, so the
    // side gutter is what gives first on a narrow screen at large text.
    final gutter = context.isCompact ? AppSpacing.sp8 : AppSpacing.sp16;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppSpacing.sp4,
        gutter,
        AppSpacing.sp8,
      ),
      // Two layouts, because this bar is laid out under BOTH kinds of
      // constraint: normally its Column gives it a finite width, and the
      // feature tour wraps it in a showcase that hands its child UNBOUNDED
      // width, where any non-zero flex throws. Bounded lets the chip flex so
      // it ellipsizes rather than overflowing a 260px phone at 2x text;
      // unbounded shrink-wraps instead.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded = constraints.maxWidth.isFinite;
          final chip = label == null ? null : _chip(l10n, label);
          return Row(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              _button(context, l10n, label != null),
              if (chip != null) ...[
                const SizedBox(width: AppSpacing.sp8),
                if (bounded) Flexible(child: chip) else chip,
              ],
            ],
          );
        },
      ),
    );
  }
}
