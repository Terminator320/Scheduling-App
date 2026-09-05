import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// What the sheet hands back: the filter, plus the street of a picked address
/// so the caller can label its chip without watching the building scan.
typedef ClientsFilterPick = ({ClientsFilter filter, String? buildingLabel});

/// The clients list's one filter surface: Type and Shared address as a single
/// radio group.
///
/// ONE group across two sections because [ClientsFilter] is a sealed one-of —
/// picking an address clears a type and vice versa. That constraint was always
/// there; the chip row hid it behind controls that looked independent.
///
/// This is also the ONLY watcher of [clientBuildingsProvider]. Keeping it here
/// rather than in `ClientsListView` is what takes the ~700-doc `orderBy('name')`
/// scan off the clients-tab open — see that provider's own doc comment.
class ClientsFilterSheet extends ConsumerWidget {
  const ClientsFilterSheet({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final ClientsFilter selected;
  final ValueChanged<ClientsFilterPick> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final buildings = ref.watch(clientBuildingsProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sp16,
                AppSpacing.sp8,
                AppSpacing.sp16,
                AppSpacing.sp8,
              ),
              child: Text(
                l10n.clients_filterTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _Option(
              label: l10n.clients_filterAll,
              value: const ClientsFilterAll(),
              selected: selected,
              onChanged: onChanged,
            ),
            _SectionHeading(l10n.clients_filterSectionType),
            // Every PICKABLE type, not a hand-listed two: dropping one would
            // make those clients unreachable by filter while their own edit
            // sheet still labels them with it.
            for (final type in ClientType.pickable)
              _Option(
                label: clientTypeLabel(l10n, type),
                value: ClientsFilterType(type),
                selected: selected,
                onChanged: onChanged,
              ),
            _Option(
              label: l10n.clients_filterArchived,
              value: const ClientsFilterArchived(),
              selected: selected,
              onChanged: onChanged,
            ),
            ...buildings.when(
              // The sheet opens immediately; the scan fills this section in.
              loading: () => [
                _SectionHeading(l10n.clients_filterSectionAddress),
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.sp16),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              ],
              // A failed scan hides the section rather than showing a broken
              // control — the type options above still work.
              error: (_, _) => const <Widget>[],
              data: (list) => list.isEmpty
                  ? const <Widget>[]
                  : [
                      _SectionHeading(l10n.clients_filterSectionAddress),
                      for (final building in list)
                        _Option(
                          label: building.street,
                          secondary: building.city.isEmpty
                              ? null
                              : building.city,
                          trailing: '${building.clientCount}',
                          value: ClientsFilterBuilding(building.key),
                          selected: selected,
                          onChanged: onChanged,
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.sp16,
      AppSpacing.sp16,
      AppSpacing.sp16,
      AppSpacing.sp4,
    ),
    child: SectionLabel(label),
  );
}

/// One row of the single radio group.
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
    this.secondary,
    this.trailing,
  });

  final String label;
  final String? secondary;
  final String? trailing;
  final ClientsFilter value;
  final ClientsFilter selected;
  final ValueChanged<ClientsFilterPick> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = selected == value;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isSelected
            ? theme.palette.primaryAccent
            : theme.palette.textMuted,
      ),
      title: Text(label),
      subtitle: secondary == null ? null : Text(secondary!),
      trailing: trailing == null
          ? null
          : Text(
              trailing!,
              style: theme.monoType.data.copyWith(
                color: theme.palette.textMuted,
              ),
            ),
      selected: isSelected,
      onTap: () => onChanged((
        filter: value,
        buildingLabel: value is ClientsFilterBuilding ? label : null,
      )),
    );
  }
}

/// Opens the filter sheet and returns the pick, or null if dismissed.
Future<ClientsFilterPick?> showClientsFilterSheet(
  BuildContext context, {
  required ClientsFilter selected,
}) => showModalBottomSheet<ClientsFilterPick>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => ClientsFilterSheet(
    selected: selected,
    onChanged: (pick) => Navigator.of(sheetContext).pop(pick),
  ),
);
