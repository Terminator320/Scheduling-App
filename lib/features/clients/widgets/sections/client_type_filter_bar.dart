import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Residential / Commercial / Property mgmt / Archived filter chips above the
/// clients list.
///
/// The type options are the fixed [ClientType.pickable] set, so unlike a
/// free-text vocabulary this needs no query to discover what to offer. Tapping
/// the selected chip clears the filter, mirroring `ClientTypeChips`. Archived
/// is a peer chip rather than a modifier: the chips are mutually exclusive, so
/// the state is one sealed [ClientsFilter], not a type plus a flag.
class ClientTypeFilterBar extends StatelessWidget {
  const ClientTypeFilterBar({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final ClientsFilter selected;
  final ValueChanged<ClientsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      label: l10n.clients_filterByType,
      // The options are a fixed three, so this scrolls (for long labels at large
      // text scale) without paying for a lazy sliver viewport.
      child: SizedBox(
        height: 48,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp16),
          child: Row(
            spacing: AppSpacing.sp8,
            children: [
              for (final type in ClientType.pickable)
                FilterChip(
                  label: Text(clientTypeLabel(l10n, type)),
                  selected: selected == ClientsFilterType(type),
                  showCheckmark: false,
                  onSelected: (_) => onChanged(
                    toggledFilter(selected, ClientsFilterType(type)),
                  ),
                ),
              FilterChip(
                label: Text(l10n.clients_filterArchived),
                selected: selected is ClientsFilterArchived,
                showCheckmark: false,
                onSelected: (_) => onChanged(
                  toggledFilter(selected, const ClientsFilterArchived()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
