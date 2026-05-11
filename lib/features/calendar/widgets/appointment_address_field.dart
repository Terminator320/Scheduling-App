import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

/// Pill-vs-field address input used by the appointment sheets.
///
/// When a client is selected and the user hasn't switched to a custom
/// address, render the read-only "client's address" pill with a
/// "Change address" button. Otherwise render the autocomplete field with
/// an optional "Use client's address" link to revert.
class AppointmentAddressField extends StatelessWidget {
  const AppointmentAddressField({
    required this.selectedClient,
    required this.useCustomAddress,
    required this.addressController,
    required this.onSwitchToCustom,
    required this.onUseClientAddress,
    super.key,
  });

  final ClientRecord? selectedClient;
  final bool useCustomAddress;
  final TextEditingController addressController;
  final VoidCallback onSwitchToCustom;
  final VoidCallback onUseClientAddress;

  @override
  Widget build(BuildContext context) {
    final showPill = selectedClient != null && !useCustomAddress;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPill)
          _AddressPill(client: selectedClient!, onChange: onSwitchToCustom)
        else ...[
          SheetFocusScroll(
            child: AddressAutocompleteField(controller: addressController),
          ),
          if (selectedClient != null && useCustomAddress) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onUseClientAddress,
              child: Text(
                context.l10n.useClientsAddress,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _AddressPill extends StatelessWidget {
  const _AddressPill({required this.client, required this.onChange});

  final ClientRecord client;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final address =
        client.address.isNotEmpty ? client.address : context.l10n.noAddress;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.r8),
            ),
            child: Icon(
              Icons.location_on_outlined,
              color: scheme.onPrimary,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.clientSAddress,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              context.l10n.changeAddress,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
