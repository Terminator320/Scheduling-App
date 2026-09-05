import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
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
  });

  final ClientRecord client;
  final Future<void> Function()? onOpen;
  final bool selected;

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
    // Archived clients drop out of the list but stay in search results, so the
    // row is the only place that can say why one looks "missing". It is the ONE
    // badge left: type moved to the filter sheet and the shared-address count
    // to the client detail, because four signals competed under one name.
    final badges = <Widget>[if (client.archived) const _ArchivedPill()];

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

/// "Archived", as a neutral pill under the address.
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
