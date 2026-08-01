import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Residential / Commercial / Property mgmt filter chips above the clients list.
///
/// The options are the fixed [ClientType.pickable] set, so unlike a free-text
/// vocabulary this needs no query to discover what to offer. Tapping the
/// selected chip clears the filter, mirroring `ClientTypeChips`.
class ClientTypeFilterBar extends StatelessWidget {
  const ClientTypeFilterBar({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// Null means no type filter is applied.
  final ClientType? selected;
  final ValueChanged<ClientType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      label: l10n.clients_filterByType,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp16),
          itemCount: ClientType.pickable.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sp8),
          itemBuilder: (context, index) {
            final type = ClientType.pickable[index];
            return Center(
              child: FilterChip(
                label: Text(clientTypeLabel(l10n, type)),
                selected: selected == type,
                showCheckmark: false,
                onSelected: (isSelected) =>
                    onChanged(isSelected ? type : null),
              ),
            );
          },
        ),
      ),
    );
  }
}
