import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/features/clients/domain/policies/client_building.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The Address filter at the end of the clients chip row — every street more
/// than one client sits at, busiest first.
///
/// A MENU rather than a chip per address, and that is the whole reason this
/// widget exists. The type options are the fixed `ClientType.pickable` set, so
/// the bar can render one chip each; addresses are a vocabulary discovered
/// from the data and there can be dozens, which a horizontally-scrolling row
/// cannot hold. It still behaves like its neighbours: picking the selected
/// address clears back to [ClientsFilterAll], mirroring `toggledFilter`.
///
/// It renders NOTHING when no address is shared. An empty menu is a control
/// that looks broken, and on a small roster this is the normal state.
class ClientAddressFilterMenu extends StatelessWidget {
  const ClientAddressFilterMenu({
    required this.buildings,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<ClientBuilding> buildings;
  final ClientsFilter selected;
  final ValueChanged<ClientsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    if (buildings.isEmpty) return const SizedBox.shrink();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final active = selected is ClientsFilterBuilding
        ? (selected as ClientsFilterBuilding).key
        : null;
    final activeBuilding = active == null
        ? null
        : buildings.where((b) => b.key == active).firstOrNull;

    return MenuAnchor(
      menuChildren: [
        for (final building in buildings)
          MenuItemButton(
            onPressed: () => onChanged(
              toggledFilter(selected, ClientsFilterBuilding(building.key)),
            ),
            leadingIcon: Icon(
              building.key == active ? Icons.check : Icons.apartment_outlined,
              size: 18,
              color: building.key == active
                  ? theme.palette.primaryAccent
                  : theme.palette.textMuted,
            ),
            child: _MenuRow(building: building),
          ),
      ],
      builder: (context, controller, _) => FilterChip(
        // The selected address replaces the generic label, so the active
        // filter is readable without opening the menu.
        label: Text(activeBuilding?.street ?? l10n.clients_filterByAddress),
        avatar: Icon(
          Icons.apartment_outlined,
          size: 18,
          color: activeBuilding != null
              ? theme.palette.primaryAccent
              : theme.palette.textMuted,
        ),
        selected: activeBuilding != null,
        showCheckmark: false,
        onSelected: (_) =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Street over "city · N units" — the count is why one address is worth
/// opening before another.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.building});

  final ClientBuilding building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = context.l10n.clients_buildingUnits(building.clientCount);
    final subtitle = [
      building.city,
      units,
    ].where((part) => part.isNotEmpty).join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(building.street, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.sp4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.palette.textMuted,
          ),
        ),
      ],
    );
  }
}
