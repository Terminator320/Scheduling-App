import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/features/clients/domain/policies/client_building.dart';
import 'package:scheduling/features/clients/widgets/sections/client_address_filter_menu.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The Address menu, then the Residential / Commercial / Building / Archived
/// filter chips above the clients list.
///
/// The type options are the fixed [ClientType.pickable] set, so unlike a
/// free-text vocabulary this needs no query to discover what to offer. Tapping
/// the selected chip clears the filter, mirroring `ClientTypeChips`. Archived
/// is a peer chip rather than a modifier: the chips are mutually exclusive, so
/// the state is one sealed [ClientsFilter], not a type plus a flag.
///
/// ADDRESSES are the free-text vocabulary that rule excludes, which is why they
/// arrive as a menu ([ClientAddressFilterMenu]) rather than a chip each — see
/// that file. It is still a peer of the chips: selecting one clears whichever
/// chip was on, because the state is one sealed value.
///
/// The menu leads the row (2026-08-29). This scrolls, so something is off-screen
/// on arrival at large text scales, and the type chips can be read by name from
/// where they sit where the menu has to be found before it can be used.
class ClientTypeFilterBar extends StatelessWidget {
  const ClientTypeFilterBar({
    required this.selected,
    required this.onChanged,
    this.buildings = const [],
    super.key,
  });

  final ClientsFilter selected;
  final ValueChanged<ClientsFilter> onChanged;

  /// Addresses shared by two or more clients. Empty renders no menu at all.
  final List<ClientBuilding> buildings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      label: l10n.clients_filterByType,
      // The chips are a fixed four and the menu is one more, so this scrolls
      // (for long labels at large text scale) without paying for a lazy sliver
      // viewport.
      child: SizedBox(
        height: 48,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp16),
          child: Row(
            spacing: AppSpacing.sp8,
            children: [
              ClientAddressFilterMenu(
                buildings: buildings,
                selected: selected,
                onChanged: onChanged,
              ),
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
