import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/list_item_tile.dart';

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
        ? AddressParser.canonicalToDisplay(client.address)
        : client.phone;
    final count = client.jobCount;
    final hasType = client.type != ClientType.unset;

    // No explicit label needed — ListItemTile's InkWell already exposes button
    // semantics and reads out the visible name and subtitle.
    return ListItemTile(
      avatarName: client.displayName,
      title: client.displayName,
      subtitle: subtitle,
      subtitleExtra: hasType ? _TypeChip(type: client.type) : null,
      selected: selected,
      onTap: () => _open(context),
      // Null until the recount trigger has run for this client — an unknown
      // count renders nothing rather than a misleading zero.
      trailing: count == null ? null : _JobCount(count: count),
    );
  }
}

/// The client's type, as a tinted pill under the address.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final ClientType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.palette.primaryAccent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp8,
          vertical: 3,
        ),
        child: Text(
          clientTypeLabel(context.l10n, type),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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
