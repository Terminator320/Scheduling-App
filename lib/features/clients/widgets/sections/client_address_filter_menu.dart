import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/features/clients/domain/policies/client_building.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// How wide the chip's label may grow before it clips. A picked street replaces
/// the generic label, and an unbounded one ("1200 Rue Sherbrooke Ouest") pushed
/// every other filter off the scrolling row.
const double _maxChipLabelWidth = 140;

/// The Address filter at the head of the clients chip row — every street more
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
///
/// It sits FIRST in the row rather than last (2026-08-29). Five controls in a
/// horizontal scroller means something starts off-screen at large text scales,
/// and the four type chips announce themselves by name where this one has to be
/// found before it can be used.
///
/// The menu paints its own surface deliberately — see [_menuStyle]. A search
/// field over these rows is designed and deferred; see
/// `docs/plans/2026-08-29-clients-address-filter.md`.
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
      style: _menuStyle(theme),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sp16,
            AppSpacing.sp4,
            AppSpacing.sp16,
            AppSpacing.sp8,
          ),
          child: SectionLabel(l10n.clients_filterByAddress),
        ),
        // Only offered while an address is actually filtering. With none
        // active it would be a row that does nothing — and worse, emitting
        // ClientsFilterAll would clear a TYPE chip this menu has no business
        // touching, since the four filters share one sealed value.
        if (selected is ClientsFilterBuilding) ...[
          MenuItemButton(
            onPressed: () => onChanged(const ClientsFilterAll()),
            leadingIcon: Icon(
              Icons.clear,
              size: 18,
              color: theme.palette.primaryAccent,
            ),
            child: Text(
              l10n.clients_filterAllAddresses,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.palette.primaryAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: AppSpacing.sp8),
        ],
        for (final building in buildings)
          _AddressMenuItem(
            building: building,
            isActive: building.key == active,
            onPressed: () => onChanged(
              toggledFilter(selected, ClientsFilterBuilding(building.key)),
            ),
          ),
      ],
      builder: (context, controller, _) => _AddressChip(
        // The selected address replaces the generic label, so the active
        // filter is readable without opening the menu.
        label: activeBuilding?.street ?? l10n.clients_filterByAddress,
        isActive: activeBuilding != null,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// The menu's own surface.
///
/// Material's default paints a menu in `surfaceContainer`, which this theme
/// maps to `AppColors.paper` — the exact `scaffoldBackgroundColor` — while
/// `surfaceTint` is deliberately transparent to kill M3 elevation tinting. The
/// two together left the open panel the same colour as the page behind it with
/// no border, so it read as a patch of the list rather than something floating
/// over it. Don't drop back to the defaults.
MenuStyle _menuStyle(ThemeData theme) => MenuStyle(
  backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
  elevation: const WidgetStatePropertyAll(3),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(vertical: AppSpacing.sp8),
  ),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.r16),
      side: BorderSide(color: theme.colorScheme.outline),
    ),
  ),
);

/// One street in the menu: street over city, with the shared-client count in
/// its own right-hand column.
///
/// The count used to be spelled into the subtitle as "city · N units", which
/// buried the one number that says which address is worth opening first.
class _AddressMenuItem extends StatelessWidget {
  const _AddressMenuItem({
    required this.building,
    required this.isActive,
    required this.onPressed,
  });

  final ClientBuilding building;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = building.clientCount;

    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Icon(
        isActive ? Icons.check : Icons.apartment_outlined,
        size: 18,
        color: isActive ? theme.palette.primaryAccent : theme.palette.textMuted,
      ),
      trailingIcon: Text(
        '$count',
        // The bare numeral is legible on screen but says nothing aloud, so the
        // plural form carries the unit for a screen reader.
        semanticsLabel: context.l10n.clients_buildingUnits(count),
        style: theme.monoType.data.copyWith(color: theme.palette.textMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            building.street,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isActive ? FontWeight.w600 : null,
            ),
          ),
          if (building.city.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sp4),
            Text(
              building.city,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The chip that opens the menu.
///
/// A chevron rather than the bare pill its neighbours use: the four beside it
/// toggle in place, this one opens something, and nothing on the old chip said
/// so. The active fill is the blue tint, not the `secondaryContainer` green a
/// selected `FilterChip` takes by default — an active address must not read as
/// a selected client TYPE.
class _AddressChip extends StatelessWidget {
  const _AddressChip({
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // onSurfaceVariant is the unselected FilterChip default, so an inactive
    // chip stays identical to the type chips beside it.
    final foreground = isActive
        ? theme.palette.primaryAccent
        : theme.colorScheme.onSurfaceVariant;

    return FilterChip(
      avatar: Icon(Icons.apartment_outlined, size: 18, color: foreground),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxChipLabelWidth),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sp4),
          Icon(Icons.keyboard_arrow_down, size: 18, color: foreground),
        ],
      ),
      labelStyle: theme.textTheme.labelLarge?.copyWith(color: foreground),
      selectedColor: theme.colorScheme.primaryContainer,
      selected: isActive,
      showCheckmark: false,
      onSelected: (_) => onPressed(),
    );
  }
}
