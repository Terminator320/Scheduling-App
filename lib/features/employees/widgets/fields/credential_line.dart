import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

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

/// Copies the email alone, for a pending row whose starting password the app
/// no longer holds. Beside [copyCredentialsToClipboard] so the two clipboard
/// payloads this feature can produce stay in one place.
void copyEmailToClipboard(String email) {
  Clipboard.setData(ClipboardData(text: email));
}

/// The "Copy both" control, beside the payload it copies.
///
/// Shared for the same reason [copyCredentialsToClipboard] is: the dialog and
/// the roster row are the two places an admin reads a starting password, and
/// they had already drifted on the confirmed-state icon. Disabled once copied
/// — the label is the whole confirmation.
class CopyCredentialsButton extends StatelessWidget {
  const CopyCredentialsButton({
    required this.copied,
    required this.onCopy,
    this.hasPassword = true,
    super.key,
  });

  final bool copied;
  final VoidCallback onCopy;

  /// False on a pending row holding no server echo — there is only an email to
  /// copy, so the label says so.
  final bool hasPassword;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: copied ? null : onCopy,
      icon: Icon(copied ? Icons.check_rounded : Icons.copy_outlined, size: 18),
      label: Text(
        copyCredentialsLabel(context, copied: copied, hasPassword: hasPassword),
      ),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// The button's label, split out for the Cupertino dialog action, which takes
/// a bare child rather than a Material button.
String copyCredentialsLabel(
  BuildContext context, {
  bool copied = false,
  bool hasPassword = true,
}) {
  if (copied) return context.l10n.common_copied;
  return hasPassword
      ? context.l10n.employees_copyBoth
      : context.l10n.employees_copyEmail;
}

/// The tint behind a credential panel. Shared so the two surfaces showing the
/// same pair sit on the same surface colour — the dialog wraps each line, the
/// roster row wraps the pair, but the fill and radius are one decision.
BoxDecoration credentialPanelDecoration(ThemeData theme) => BoxDecoration(
  color: theme.palette.sheetRow,
  borderRadius: BorderRadius.circular(AppRadius.r12),
);
