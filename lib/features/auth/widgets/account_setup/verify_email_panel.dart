import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';

/// The email-verification step: send the link, then confirm it was opened.
///
/// This is a real gate, not a nudge — `completeEmployeeSetup` refuses without
/// `email_verified`, because the account was created on a password every admin
/// knows and control of the mailbox is the only thing that identifies the
/// person on this screen.
class VerifyEmailPanel extends StatelessWidget {
  const VerifyEmailPanel({
    required this.hasSent,
    required this.isSending,
    required this.isChecking,
    required this.notice,
    required this.onSend,
    required this.onCheck,
    super.key,
  });

  final bool hasSent;
  final bool isSending;
  final bool isChecking;
  final String? notice;
  final VoidCallback onSend;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final message = notice;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sp16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  l10n.auth_verifyEmailTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sp8),
          Text(
            l10n.auth_verifyEmailBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.sp8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sp12),
          // Wrap, not Row: at large text scales the two labels are long enough
          // to overflow side by side.
          Wrap(
            spacing: AppSpacing.sp8,
            runSpacing: AppSpacing.sp8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('sendVerificationEmail'),
                onPressed: isSending ? null : onSend,
                icon: BusyButtonIcon(
                  isBusy: isSending,
                  icon: Icons.send_outlined,
                ),
                label: Text(
                  hasSent
                      ? l10n.auth_resendVerificationEmail
                      : l10n.auth_sendVerificationEmail,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('checkVerification'),
                onPressed: isChecking ? null : onCheck,
                icon: BusyButtonIcon(
                  isBusy: isChecking,
                  icon: Icons.refresh,
                ),
                label: Text(l10n.auth_checkVerification),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
