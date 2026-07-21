import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

// Body for the delete-account confirm (shown via showConfirmDialog).
class DeleteAccountWarningContent extends StatelessWidget {
  const DeleteAccountWarningContent({required this.isAdmin, super.key});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.settings_deleteAccountConfirmBody),
        if (isAdmin) ...[
          const SizedBox(height: AppSpacing.sp12),
          Text(
            context.l10n.settings_deleteAccountAdminWarning,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class DeleteAccountReauthDialog extends StatefulWidget {
  const DeleteAccountReauthDialog({super.key});

  @override
  State<DeleteAccountReauthDialog> createState() =>
      _DeleteAccountReauthDialogState();
}

class _DeleteAccountReauthDialogState extends State<DeleteAccountReauthDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The re-auth prompt opens right after the adaptive delete confirm
    // (showConfirmDialog), so it must match that dialog's platform look —
    // a Material AlertDialog straight after a Cupertino confirm is jarring.
    if (context.isCupertino) return _buildCupertino(context);
    return _buildMaterial(context);
  }

  Widget _buildCupertino(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(context.l10n.settings_confirmYourPassword),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.settings_confirmYourPasswordToDelete),
          const SizedBox(height: AppSpacing.sp12),
          CupertinoTextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            placeholder: context.l10n.common_password,
            onSubmitted: (value) => Navigator.of(context).pop(value),
            suffix: Semantics(
              button: true,
              label: _obscure
                  ? context.l10n.auth_showPassword
                  : context.l10n.auth_hidePassword,
              child: GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sp8,
                  ),
                  child: Icon(
                    _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                    size: 20,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.common_cancel),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.l10n.settings_deletePermanently),
        ),
      ],
    );
  }

  Widget _buildMaterial(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.l10n.settings_confirmYourPassword),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.settings_confirmYourPasswordToDelete),
          const SizedBox(height: AppSpacing.sp12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.common_password,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure
                    ? context.l10n.auth_showPassword
                    : context.l10n.auth_hidePassword,
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.common_cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.l10n.settings_deletePermanently),
        ),
      ],
    );
  }
}
