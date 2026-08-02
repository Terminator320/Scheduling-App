import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// One labelled credential — a muted mono label over the value.
///
/// Selectable because copy-to-clipboard can fail, and reading a password off
/// the screen to type it by hand is the floor this has to keep working at.
///
/// Shared by the new-account dialog and the pending-account roster row so the
/// two surfaces that show the same credential pair can't drift on how a
/// password is presented. The tinted container is the caller's job: the dialog
/// tints each line, the roster row tints the pair.
class CredentialLine extends StatelessWidget {
  const CredentialLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.monoType.micro.copyWith(color: theme.palette.textMuted),
        ),
        const SizedBox(height: AppSpacing.sp4),
        SelectableText(
          value,
          style: theme.monoType.data.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Copies both halves together: an admin pasting this into a message wants the
/// pair, and copying only the password loses which account it opens.
///
/// The single owner of that payload format. This is the ONE sanctioned egress
/// of a starting password, so both surfaces must put the same thing on the
/// clipboard — never inline `'$email\n$password'` at a call site again.
void copyCredentialsToClipboard({
  required String email,
  required String password,
}) {
  Clipboard.setData(ClipboardData(text: '$email\n$password'));
}
