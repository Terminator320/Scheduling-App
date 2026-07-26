import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Shows the one-time signup code after creating an invite — an adaptive
/// dialog that picks Cupertino or Material to match the platform.
Future<void> showSignupCodeDialog(
  BuildContext context, {
  required String name,
  required String code,
}) {
  if (context.isCupertino) {
    // showCupertinoDialog is non-dismissible by default, which matches what
    // we do in the Material branch.
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => _SignupCodeDialog(name: name, code: code),
    );
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SignupCodeDialog(name: name, code: code),
  );
}

class _SignupCodeDialog extends StatefulWidget {
  const _SignupCodeDialog({required this.name, required this.code});

  final String name;
  final String code;

  @override
  State<_SignupCodeDialog> createState() => _SignupCodeDialogState();
}

class _SignupCodeDialogState extends State<_SignupCodeDialog> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.employees_shareThisCodeWith(widget.name)),
        const SizedBox(height: AppSpacing.sp16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sp12,
            horizontal: AppSpacing.sp8,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.r8),
          ),
          child: SelectableText(
            widget.code,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final copyLabel = _copied
        ? context.l10n.common_copied
        : context.l10n.employees_copyCode;

    if (context.isCupertino) {
      return CupertinoAlertDialog(
        title: Text(context.l10n.employees_signupCodeTitle),
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
            child: Text(context.l10n.common_close),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(context.l10n.employees_signupCodeTitle),
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
          child: Text(context.l10n.common_close),
        ),
      ],
    );
  }
}
