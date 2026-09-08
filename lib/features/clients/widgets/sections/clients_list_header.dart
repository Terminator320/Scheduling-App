import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/clients_sort.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One line above the list: how many clients on the left, the order on the
/// right.
class ClientsListHeader extends StatelessWidget {
  const ClientsListHeader({
    required this.count,
    required this.sort,
    required this.onSortChanged,
    super.key,
  });

  /// Null while the first page is still settling — an unknown count renders
  /// nothing rather than a misleading zero, the same rule the row's job count
  /// follows.
  final int? count;

  final ClientsSort sort;
  final ValueChanged<ClientsSort> onSortChanged;

  static String sortLabel(AppLocalizations l10n, ClientsSort sort) =>
      switch (sort) {
        ClientsSort.name => l10n.clients_sortByName,
        ClientsSort.mostJobs => l10n.clients_sortMostJobs,
        ClientsSort.recentlyAdded => l10n.clients_sortRecentlyAdded,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        0,
        AppSpacing.sp8,
        AppSpacing.sp4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == null ? '' : l10n.clients_countLabel(count!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.palette.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Flexible, not a fixed child: at 260px with 2x text the count and
          // the sort label together exceed the row, so both must be allowed to
          // ellipsize rather than one overflowing.
          Flexible(
            child: PopupMenuButton<ClientsSort>(
              tooltip: l10n.clients_sort,
              initialValue: sort,
              onSelected: onSortChanged,
              itemBuilder: (context) => [
                for (final option in ClientsSort.values)
                  PopupMenuItem<ClientsSort>(
                    value: option,
                    child: Text(sortLabel(l10n, option)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sp8,
                  vertical: AppSpacing.sp8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        sortLabel(l10n, sort),
                        style: theme.textTheme.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
