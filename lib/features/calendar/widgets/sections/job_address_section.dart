import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/widgets/fields/appointment_address_field.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The job address in its WHO home: the client's own previous job addresses
/// first, and the billed autocomplete only once none of them is the answer.
class JobAddressSection extends StatefulWidget {
  const JobAddressSection({
    required this.selectedClient,
    required this.useCustomAddress,
    required this.addressController,
    required this.previousAddresses,
    required this.onPickPrevious,
    required this.onSwitchToCustom,
    required this.onUseClientAddress,
    super.key,
    this.optional = false,
  });

  final ClientRecord? selectedClient;
  final bool useCustomAddress;
  final TextEditingController addressController;

  /// Where this client's earlier jobs were, newest-first.
  final List<String> previousAddresses;

  final ValueChanged<String> onPickPrevious;
  final VoidCallback onSwitchToCustom;
  final VoidCallback onUseClientAddress;

  /// Marks the field "(Optional)" — a personal block may name a place but
  /// doesn't have to.
  final bool optional;

  @override
  State<JobAddressSection> createState() => _JobAddressSectionState();
}

class _JobAddressSectionState extends State<JobAddressSection> {
  // An address already typed means the autocomplete is the answer, so the
  // previous list must not hide it.
  late bool _searching = widget.addressController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final client = widget.selectedClient;
    final showPrevious =
        widget.useCustomAddress &&
        client != null &&
        widget.previousAddresses.isNotEmpty &&
        !_searching;
    if (!showPrevious) return _field();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviousAddresses(
          client: client,
          addresses: widget.previousAddresses,
          onPick: widget.onPickPrevious,
          onSearch: () => setState(() => _searching = true),
        ),
      ],
    );
  }

  Widget _field() => AppointmentAddressField(
    selectedClient: widget.selectedClient,
    useCustomAddress: widget.useCustomAddress,
    addressController: widget.addressController,
    optional: widget.optional,
    onSwitchToCustom: widget.onSwitchToCustom,
    onUseClientAddress: widget.onUseClientAddress,
  );
}

class _PreviousAddresses extends StatelessWidget {
  const _PreviousAddresses({
    required this.client,
    required this.addresses,
    required this.onPick,
    required this.onSearch,
  });

  final ClientRecord client;
  final List<String> addresses;
  final ValueChanged<String> onPick;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final name = client.firstName.trim().isNotEmpty
        ? client.firstName.trim()
        : client.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sp4),
          child: Text(
            l10n.calendar_beenHereBefore(name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.monoType.groupLabel,
          ),
        ),
        DecoratedBox(
          decoration: appCardDecoration(theme, color: theme.palette.sheetRow),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            child: Column(
              children: [
                for (final address in addresses) ...[
                  if (address != addresses.first)
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  _AddressRow(label: address, onTap: () => onPick(address)),
                ],
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                _AddressRow(
                  label: l10n.calendar_searchForAnotherAddress,
                  icon: Icons.search,
                  onTap: onSearch,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.label, required this.onTap, this.icon});

  final String label;
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
          vertical: AppSpacing.sp12,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sp8),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: icon == null ? scheme.onSurface : scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
