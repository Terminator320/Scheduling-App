import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// The attached client, confirmed. The NUMBER is the headline because it is
/// what was just typed and read back over the phone; the name qualifies it.
class SelectedClientCard extends StatelessWidget {
  const SelectedClientCard({
    required this.client,
    required this.useClientAddress,
    required this.onChange,
    required this.onRemove,
    required this.onUseClientAddressChanged,
    super.key,
    this.lastVisitLabel,
  });

  final ClientRecord client;
  final bool useClientAddress;
  final String? lastVisitLabel;
  final VoidCallback onChange;
  final VoidCallback onRemove;
  final ValueChanged<bool> onUseClientAddressChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final address = client.fullAddress.trim();
    return DecoratedBox(
      decoration: appCardDecoration(
        theme,
        radius: AppRadius.r16,
        color: theme.palette.sheetRow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sp12),
            child: _identity(theme, l10n),
          ),
          if (address.isNotEmpty) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sp12),
              child: _address(theme, l10n, address),
            ),
          ],
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          _actions(theme, l10n),
        ],
      ),
    );
  }

  Widget _identity(ThemeData theme, AppLocalizations l10n) {
    final jobs = client.jobCount;
    final lastVisit = lastVisitLabel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppAvatar(name: client.displayName, size: AvatarSize.sm),
        const SizedBox(width: AppSpacing.sp8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatPhoneNumber(client.phone),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.monoType.metric,
              ),
              Text(
                client.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // A lazily-backfilled count renders nothing rather than "0 jobs".
              if (jobs != null && lastVisit != null)
                Text(
                  l10n.clients_jobsAndLastVisit(jobs, lastVisit),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _address(ThemeData theme, AppLocalizations l10n, String address) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            address,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.sp4),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.calendar_useThisAddressForTheJob,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Switch.adaptive(
                value: useClientAddress,
                activeTrackColor: theme.colorScheme.primary,
                onChanged: onUseClientAddressChanged,
              ),
            ],
          ),
        ],
      );

  Widget _actions(ThemeData theme, AppLocalizations l10n) => IntrinsicHeight(
    child: Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: onChange,
            child: Text(
              l10n.clients_changeClient,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: TextButton(
            onPressed: onRemove,
            // A text action takes the lifted foreground red; dangerFill is for
            // FILLED destructive buttons.
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(
              l10n.clients_removeClient,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    ),
  );
}
