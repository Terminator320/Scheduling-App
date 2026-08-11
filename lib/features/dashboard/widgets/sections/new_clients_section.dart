import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Clients added over the dashboard window — a count, a sparkline of the 8
/// weekly buckets, and the most recent few as tappable rows.
///
/// Archived clients are already excluded upstream (`newClientsProvider`): the
/// dashboard answers *what should I look at now*, and an archived client is
/// one you decided not to look at.
class NewClientsSection extends StatelessWidget {
  const NewClientsSection({
    required this.clients,
    required this.weeklyCounts,
    super.key,
  });

  /// Newest first.
  final List<ClientRecord> clients;

  /// One count per week bucket, oldest first — the same buckets the trends
  /// chart uses.
  final List<int> weeklyCounts;

  /// Enough to show momentum without turning the dashboard into the clients
  /// list, which is one tap away.
  static const int rowLimit = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final total = weeklyCounts.fold(0, (sum, v) => sum + v);
    // Built once per rebuild, never per row: constructing a DateFormat
    // verifies the locale and parses a skeleton, and doing that inside an item
    // builder is what made the calendar build 30-90 of them per frame.
    final dateFormat = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_newClients),
        const SizedBox(height: AppSpacing.sp8),
        Container(
          decoration: appCardDecoration(theme, color: scheme.surface),
          padding: const EdgeInsets.all(AppSpacing.sp16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboard_newClientsTotal(total),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sp8),
              Semantics(
                label:
                    '${l10n.dashboard_newClients}: '
                    '${l10n.dashboard_newClientsTotal(total)}',
                child: ExcludeSemantics(
                  child: NewClientSparkline(
                    values: weeklyCounts,
                    color: scheme.primary,
                  ),
                ),
              ),
              if (clients.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sp12),
                  child: Text(
                    l10n.dashboard_newClientsEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final client in clients.take(rowLimit))
                  _NewClientRow(client: client, dateFormat: dateFormat),
            ],
          ),
        ),
      ],
    );
  }
}

class _NewClientRow extends StatelessWidget {
  const _NewClientRow({required this.client, required this.dateFormat});

  final ClientRecord client;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showClientDetailSheet(context, client),
      borderRadius: BorderRadius.circular(AppRadius.r8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                client.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sp8),
            Text(
              dateFormat.format(client.createdAt!),
              style: theme.monoType.data.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 8-bucket sparkline. Public because the section owns it now but the
/// trends card rendered it first — one copy, not two.
class NewClientSparkline extends StatelessWidget {
  const NewClientSparkline({
    required this.values,
    required this.color,
    super.key,
  });

  final List<int> values;
  final Color color;

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    var maxValue = 0;
    for (final v in values) {
      if (v > maxValue) maxValue = v;
    }
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: SizedBox(
                  height: maxValue == 0 ? 0 : _height * v / maxValue,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
