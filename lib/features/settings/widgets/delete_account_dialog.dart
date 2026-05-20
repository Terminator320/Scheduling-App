import 'package:flutter/material.dart';

import 'package:scheduling/l10n/l10n.dart';

class DeleteAccountDialog extends StatelessWidget {
  const DeleteAccountDialog({required this.isAdmin, super.key});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.l10n.deleteAccountConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.deleteAccountConfirmBody),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            Text(
              context.l10n.deleteAccountAdminWarning,
              style: TextStyle(color: scheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.deletePermanently),
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.l10n.confirmYourPassword),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.confirmYourPasswordToDelete),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.password,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
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
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.l10n.deletePermanently),
        ),
      ],
    );
  }
}
