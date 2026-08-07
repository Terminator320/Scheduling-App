import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One-tap client-type chips. Tapping the selected chip clears it back to
/// [ClientType.unset] — the type is optional and must stay un-pickable-back.
///
/// The chips are a label and nothing else: they never swap, reveal or hide a
/// field (owner change 6, 2026-08-01). `name` is what the clients list orders
/// by and Firestore drops docs missing the orderBy field, so the required name
/// field must never be hideable behind a chip.
class ClientTypeChips extends StatelessWidget {
  const ClientTypeChips({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ClientType value;
  final ValueChanged<ClientType> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: AppSpacing.sp8,
      runSpacing: AppSpacing.sp8,
      children: [
        for (final type in ClientType.pickable)
          ChoiceChip(
            label: Text(clientTypeLabel(l10n, type)),
            selected: value == type,
            onSelected: (selected) =>
                onChanged(selected ? type : ClientType.unset),
          ),
      ],
    );
  }
}
