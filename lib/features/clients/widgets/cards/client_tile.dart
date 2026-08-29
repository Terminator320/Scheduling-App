import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/list_item_tile.dart';
import 'package:scheduling/shared/widgets/feedback/status_pill.dart';

class ClientTile extends StatelessWidget {
  const ClientTile({
    required this.client,
    super.key,
    this.onOpen,
    this.selected = false,
    this.buildingCount,
  });

  final ClientRecord client;
  final Future<void> Function()? onOpen;
  final bool selected;

  /// How many clients share this one's street address, when that is more than
  /// one. Passed IN rather than looked up: the list reduces the whole window
  /// once and hands each row its number, the way the team roster's "jobs
  /// today" count does — a per-row provider watch would be one listener per
  /// visible client. Null on any surface with no index to hand (the booking
  /// flow's client picker), which simply shows no pill.
  final int? buildingCount;

  Future<void> _open(BuildContext context) async {
    if (onOpen != null) {
      await onOpen!();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClientDetailSheet(client: client),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The address is what identifies a job site at a glance; phone is the
    // fallback for a client who has no address on file.
    final subtitle = client.address.trim().isNotEmpty
        ? client.fullAddress
        : client.phone;
    final count = client.jobCount;
    final hasType = client.type != ClientType.unset;
    // Archived clients drop out of the list but stay in search results, so the
    // row is the only place that can say why one looks "missing".
    final isShared = (buildingCount ?? 0) > 1;
    final badges = <Widget>[
      if (client.archived) const _ArchivedPill(),
      if (hasType) _TypeChip(type: client.type),
      // Skipped when the type chip beside it already reads "Building" — the
      // two pills carry the same word and would render as a duplicate.
      if (isShared && client.type != ClientType.building)
        const _BuildingPill(),
    ];

    // Resolved once: `displayName` is an uncached getter that runs `stripPhone`
    // (two regex passes), and this rebuilds per row on the paginated list and
    // per keystroke in the booking-flow picker.
    final displayName = client.displayName;

    // No explicit label needed — ListItemTile's InkWell already exposes button
    // semantics and reads out the visible name and subtitle.
    return ListItemTile(
      avatarName: displayName,
      title: displayName,
      subtitle: subtitle,
      subtitleExtra: badges.isEmpty
          ? null
          : Wrap(
              spacing: AppSpacing.sp8,
              runSpacing: AppSpacing.sp4,
              children: badges,
            ),
      selected: selected,
      onTap: () => _open(context),
      // Null until the recount trigger has run for this client — an unknown
      // count renders nothing rather than a misleading zero.
      trailing: count == null ? null : _JobCount(count: count),
    );
  }
}

/// "Archived", as a neutral pill under the address. Neutral rather than
/// warning-tinted: archiving is a routine filing action, not a fault. Takes
/// the same slot colours `UserStatusChip` gives a disabled account, which
/// carries the same "out of the working set" meaning.
class _ArchivedPill extends StatelessWidget {
  const _ArchivedPill();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StatusPill(
      label: context.l10n.clients_filterArchived,
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
      radius: AppRadius.r8,
    );
  }
}

/// The client's type, as a tinted pill under the address.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final ClientType type;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).palette.primaryAccent;
    return StatusPill(
      label: clientTypeLabel(context.l10n, type),
      background: color.withValues(alpha: 0.10),
      foreground: color,
      radius: AppRadius.r8,
    );
  }
}

/// "Building", as a neutral pill under the address — this client's address is
/// shared with others. Neutral rather than accented: it is a fact about the
/// site, not a status, and the accent slot beside it already belongs to the
/// client's type. It says WHAT the site is, not how many neighbours the row
/// has: the count belongs to the Address filter menu, where it ranks one
/// building against another.
///
/// Deliberately NOT tappable. The whole row is one `InkWell` that opens the
/// client, so a tappable pill inside it is a nested gesture on a 48px target;
/// the Address menu above the list is where filtering to a building belongs.
class _BuildingPill extends StatelessWidget {
  const _BuildingPill();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StatusPill(
      label: context.l10n.clients_typeBuilding,
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
      radius: AppRadius.r8,
    );
  }
}

/// Right-aligned stacked figure: the count over a mono JOBS micro-label.
class _JobCount extends StatelessWidget {
  const _JobCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$count', style: theme.monoType.metric),
        Text(
          context.l10n.clients_jobsCountLabel,
          style: theme.monoType.micro.copyWith(color: theme.palette.textMuted),
        ),
      ],
    );
  }
}
