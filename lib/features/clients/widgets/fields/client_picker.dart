import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/features/calendar/domain/models/recent_client.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_search_status.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

/// The add-job client step: a mode switch, one field, and whatever the current
/// search has to say about it.
///
/// Never attaches on its own — every row needs a tap — and never dismisses the
/// keyboard except from that tap.
class ClientPicker extends StatelessWidget {
  const ClientPicker({
    required this.controller,
    required this.results,
    required this.status,
    required this.recentClients,
    required this.isSearching,
    required this.onChanged,
    required this.onModeChanged,
    required this.onSelect,
    required this.onSelectRecent,
    required this.onRetry,
    super.key,
    this.errorText,
    this.onAddNew,
  });

  final TextEditingController controller;
  final List<ClientRecord> results;
  final ClientSearchStatus status;
  final List<RecentClient> recentClients;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final ValueChanged<ClientQueryMode> onModeChanged;
  final ValueChanged<ClientRecord> onSelect;

  /// A recents row hands back the RECENT, not a record built from it — the
  /// host resolves the real client so both paths produce the same draft.
  final ValueChanged<RecentClient> onSelectRecent;
  final VoidCallback onRetry;
  final String? errorText;

  /// When non-null the list ends with a create-from-this-number row.
  final VoidCallback? onAddNew;

  /// A finished North-American number, for the "n of 10" tally.
  static const int _nanpLength = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isPhone = status.mode == ClientQueryMode.phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeSwitch(mode: status.mode, onChanged: onModeChanged),
        const SizedBox(height: AppSpacing.sp8),
        TextFormField(
          controller: controller,
          keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
          inputFormatters: isPhone ? const [PhoneInputFormatter()] : null,
          textInputAction: TextInputAction.search,
          decoration: formInputDecoration(
            context,
            l10n.clients_tapPhoneToStart,
          ).copyWith(errorText: errorText),
          onChanged: onChanged,
        ),
        if (status.isHolding) ...[
          const SizedBox(height: AppSpacing.sp8),
          _Tally(typed: status.digitsTyped, total: _nanpLength),
        ],
        const SizedBox(height: AppSpacing.sp8),
        _body(context, l10n),
      ],
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isSearching) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.sp12),
        child: AdaptiveProgressIndicator(),
      );
    }
    // A failure that renders as "no clients found" is how a duplicate gets
    // created for a client who is already on file.
    if (status.failed) return _failure(context, l10n);
    if (controller.text.trim().isEmpty || status.isHolding) {
      return _recents(context, l10n);
    }
    return _results(context, l10n);
  }

  Widget _failure(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.clients_searchFailed,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l10n.clients_retrySearch)),
      ],
    );
  }

  Widget _recents(BuildContext context, AppLocalizations l10n) {
    final digits = ClientSearchPolicy.digitsOnly(controller.text);
    final matching = [
      for (final recent in recentClients)
        if (matchesDigits(recent, digits)) recent,
    ];
    if (matching.isEmpty) return const SizedBox.shrink();
    return _Panel(
      header: l10n.clients_recentClients,
      count: null,
      rows: [
        for (final recent in matching)
          _Row(
            headline: formatPhoneNumber(recent.phone),
            detail: recent.name,
            // A recent is a whole client the admin already booked, so the row
            // itself is the affordance — no second confirm step.
            onTap: () {
              FocusScope.of(context).unfocus();
              onSelectRecent(recent);
            },
          ),
      ],
    );
  }

  Widget _results(BuildContext context, AppLocalizations l10n) {
    if (results.isEmpty && onAddNew == null) {
      return Text(
        l10n.clients_noClientsFound,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return _Panel(
      header: _header(l10n),
      count: results.isEmpty ? null : l10n.clients_matchCount(results.length),
      rows: [
        for (final client in results)
          _Row(
            headline: client.phone.trim().isEmpty
                ? client.displayName
                : formatPhoneNumber(client.phone),
            detail: client.displayName,
            action: l10n.clients_attach,
            onTap: () => _attach(context, client),
          ),
        if (onAddNew != null)
          _Row(
            headline: l10n.clients_noneOfTheseNewClient,
            icon: Icons.person_add_alt_1,
            onTap: () {
              FocusScope.of(context).unfocus();
              onAddNew!();
            },
          ),
      ],
    );
  }

  /// A fallback rung answered a query he did not type, so those are near misses
  /// and must never read as matches. "Exact match" is reserved for the one case
  /// that IS one — a canonical phone rung with a single hit; a text query is a
  /// substring test server-side, so several results under that header
  /// contradict themselves and invite attaching the wrong client.
  String _header(AppLocalizations l10n) {
    if (status.isFallback) return l10n.clients_closestNumbers;
    if (status.mode == ClientQueryMode.phone && results.length == 1) {
      return l10n.clients_exactMatch;
    }
    return l10n.clients_searchResults;
  }

  /// The ONE place allowed to drop the keyboard.
  void _attach(BuildContext context, ClientRecord client) {
    FocusScope.of(context).unfocus();
    onSelect(client);
  }
}

/// Phone / Name-or-address, rendered whether or not the field has focus so
/// choosing a name search never opens a phone pad first.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final ClientQueryMode mode;
  final ValueChanged<ClientQueryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: l10n.clients_modePhone,
              selected: mode == ClientQueryMode.phone,
              onTap: () => onChanged(ClientQueryMode.phone),
            ),
          ),
          Expanded(
            child: _Segment(
              label: l10n.clients_modeNameOrAddress,
              selected: mode == ClientQueryMode.text,
              onTap: () => onChanged(ClientQueryMode.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp8,
          vertical: AppSpacing.sp8,
        ),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.r12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// "4 of 10 · Keep going" — the number is still too short to be selective.
class _Tally extends StatelessWidget {
  const _Tally({required this.typed, required this.total});

  final int typed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Wrap(
      spacing: AppSpacing.sp8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.clients_digitsTyped(typed, total),
          style: theme.monoType.data,
        ),
        Text(
          l10n.clients_keepGoing,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A titled block of tappable rows. Paints its own background, so the rows are
/// hand-built rather than `ListTile`s.
class _Panel extends StatelessWidget {
  const _Panel({required this.header, required this.count, required this.rows});

  final String header;
  final String? count;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sp4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  header,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.monoType.groupLabel,
                ),
              ),
              if (count != null)
                Text(
                  count!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        SheetPanel(children: rows),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.headline,
    required this.onTap,
    this.detail,
    this.action,
    this.icon,
  });

  final String headline;
  final String? detail;
  final String? action;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp12,
          vertical: AppSpacing.sp8,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: AppSpacing.sp8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: icon == null
                        ? theme.monoType.metric
                        : theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                  if (detail != null && detail!.trim().isNotEmpty)
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sp8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  action!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
