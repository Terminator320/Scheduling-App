import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/domain/models/new_account_credentials.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Shows the sign-in credentials after creating an employee account — an
/// adaptive dialog that picks Cupertino or Material to match the platform.
///
/// The password is the shared starting one the server just set, echoed back
/// rather than hardcoded here so the dialog can never show something the
/// account was not actually given.
Future<void> showNewAccountDialog(
  BuildContext context, {
  required String name,
  required NewAccountCredentials credentials,
}) {
  if (context.isCupertino) {
    // showCupertinoDialog is non-dismissible by default, which matches what
    // we do in the Material branch.
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) =>
          _NewAccountDialog(name: name, credentials: credentials),
    );
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _NewAccountDialog(name: name, credentials: credentials),
  );
}

class _NewAccountDialog extends StatefulWidget {
  const _NewAccountDialog({required this.name, required this.credentials});

  final String name;
  final NewAccountCredentials credentials;

  @override
  State<_NewAccountDialog> createState() => _NewAccountDialogState();
}

class _NewAccountDialogState extends State<_NewAccountDialog> {
  bool _copied = false;

  /// Copies both halves together: an admin pasting this into a message wants
  /// the pair, and copying only the password loses which account it opens.
  void _copy() {
    Clipboard.setData(
      ClipboardData(
        text: '${widget.credentials.email}\n${widget.credentials.password}',
      ),
    );
    setState(() => _copied = true);
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.employees_shareTheseWith(widget.name)),
        const SizedBox(height: AppSpacing.sp16),
        _CredentialRow(
          label: l10n.common_email,
          value: widget.credentials.email,
        ),
        const SizedBox(height: AppSpacing.sp8),
        _CredentialRow(
          label: l10n.employees_temporaryPassword,
          value: widget.credentials.password,
        ),
        const SizedBox(height: AppSpacing.sp12),
        Text(
          l10n.employees_theyWillChooseTheirOwnPassword,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final copyLabel = _copied ? l10n.common_copied : l10n.employees_copyBoth;

    if (context.isCupertino) {
      return CupertinoAlertDialog(
        title: Text(l10n.employees_accountCreatedTitle),
        // Wrap in a transparent Material widget so the selectable text still
        // gets its Material toolbar inside the Cupertino dialog.
        content: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sp8),
            child: _buildBody(context),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: _copied ? null : _copy,
            child: Text(copyLabel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_close),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(l10n.employees_accountCreatedTitle),
      content: _buildBody(context),
      actions: [
        TextButton.icon(
          icon: Icon(
            _copied ? Icons.check_outlined : Icons.copy_outlined,
            size: 18,
          ),
          label: Text(copyLabel),
          onPressed: _copied ? null : _copy,
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_close),
        ),
      ],
    );
  }
}

/// One labelled, selectable credential. Selectable because copy-to-clipboard
/// can fail and reading a password off a screen to type it by hand is the
/// floor this has to keep working at.
class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sp8,
        horizontal: AppSpacing.sp12,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.monoType.micro.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sp4),
          SelectableText(
            value,
            style: theme.monoType.data.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
