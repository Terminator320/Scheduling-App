import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_search_status.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/attached_dropdown.dart';
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
    required this.isSearching,
    required this.onChanged,
    required this.onModeChanged,
    required this.onSelect,
    required this.onRetry,
    super.key,
    this.errorText,
    this.onAddNew,
  });

  final TextEditingController controller;
  final List<ClientRecord> results;
  final ClientSearchStatus status;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final ValueChanged<ClientQueryMode> onModeChanged;
  final ValueChanged<ClientRecord> onSelect;
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
          decoration: formInputDecoration(context, l10n.clients_tapPhoneToStart)
              .copyWith(
                errorText: errorText,
                // The spinner rides the FIELD, not the list: replacing the
                // results with a centred indicator made the list jump on
                // every keystroke.
                suffixIcon: isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.sp12),
                        child: AdaptiveProgressIndicator(size: 16),
                      )
                    : null,
              ),
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
    // A failure that renders as "no clients found" is how a duplicate gets
    // created for a client who is already on file.
    if (status.failed) return _failure(context, l10n);
    if (controller.text.trim().isEmpty || status.isHolding) {
      return const SizedBox.shrink();
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

  Widget _results(BuildContext context, AppLocalizations l10n) {
    if (results.isEmpty && onAddNew == null) {
      return Text(
        l10n.clients_noClientsFound,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final isPhone = status.mode == ClientQueryMode.phone;
    return _Dropdown(
      // Option A drops the panel header, so the fallback rung keeps its
      // warning as a caption: those rows answer a query nobody typed and must
      // never read as matches.
      caption: status.isFallback ? l10n.clients_noExactMatchClosest : null,
      children: [
        for (final client in results)
          _DropdownRow(
            headline: isPhone && client.phone.trim().isNotEmpty
                ? formatPhoneNumber(client.phone)
                : client.displayName,
            detail: isPhone
                ? client.displayName
                : (client.phone.trim().isEmpty
                      ? null
                      : formatPhoneNumber(client.phone)),
            mono: isPhone,
            action: l10n.clients_attach,
            onTap: () => _attach(context, client),
          ),
        if (onAddNew != null)
          _DropdownRow(
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

/// The client results, in the same attached list the address picker uses, so
/// the two fields behave identically.
class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.children, this.caption});

  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AttachedDropdown(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (caption != null)
            Container(
              width: double.infinity,
              color: theme.statusColors.warningContainer,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sp12,
                vertical: AppSpacing.sp8,
              ),
              child: Text(
                caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.monoType.groupLabel.copyWith(
                  color: theme.statusColors.onWarningContainer,
                ),
              ),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 || caption != null)
              Divider(height: 1, color: scheme.outlineVariant),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.headline,
    required this.onTap,
    this.detail,
    this.action,
    this.icon,
    this.mono = false,
  });

  final String headline;
  final String? detail;
  final String? action;
  final IconData? icon;

  /// A phone number reads as a number, not as prose.
  final bool mono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final TextStyle? headlineStyle;
    if (icon != null) {
      headlineStyle = theme.textTheme.bodyMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      );
    } else if (mono) {
      headlineStyle = theme.monoType.metric;
    } else {
      headlineStyle = theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      );
    }
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
                    style: headlineStyle,
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
