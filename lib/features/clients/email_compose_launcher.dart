import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bottom-sheet chooser for composing an email — system default mail app,
/// Gmail, or Outlook — mirroring `AddressMapLauncher`'s map-app picker.
class EmailComposeLauncher {
  const EmailComposeLauncher._();

  static Future<void> showEmailChoices(
    BuildContext context,
    WidgetRef ref, {
    required String email,
  }) async {
    final address = email.trim();
    if (address.isEmpty) return;
    final encoded = Uri.encodeComponent(address);

    final options = <_EmailOption>[
      _EmailOption(
        label: context.l10n.clients_defaultMailApp,
        icon: Icons.mail_outline,
        uri: Uri(scheme: 'mailto', path: address),
      ),
      _EmailOption(
        label: context.l10n.clients_gmail,
        icon: Icons.email_outlined,
        uri: Uri.parse(
          'https://mail.google.com/mail/?view=cm&fs=1&to=$encoded',
        ),
      ),
      _EmailOption(
        label: context.l10n.clients_outlook,
        icon: Icons.email_outlined,
        uri: Uri.parse(
          'https://outlook.office.com/mail/deeplink/compose?to=$encoded',
        ),
      ),
    ];

    final errorMessage = context.l10n.error_couldNotOpenEmail;

    // iOS: native CupertinoActionSheet. Android: the existing Material sheet
    // (drag handle + address header). Both resolve to the chosen URI, launched
    // once below.
    final Uri? chosen;
    if (context.isCupertino) {
      chosen = await showAdaptiveActionSheet<Uri>(
        context,
        title: context.l10n.clients_emailWith,
        message: address,
        actions: [
          for (final option in options)
            AdaptiveSheetAction(
              value: option.uri,
              label: option.label,
              icon: option.icon,
            ),
        ],
      );
    } else {
      chosen = await showModalBottomSheet<Uri>(
        context: context,
        showDragHandle: true,
        sheetAnimationStyle: AppMotion.sheetStyle,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.clients_emailWith,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...options.map(
                    (option) => ListTile(
                      leading: Icon(option.icon),
                      title: Text(option.label),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.pop(sheetContext, option.uri),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (chosen == null) return;
    try {
      final opened = await launchUrl(
        chosen,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ref.read(noticeServiceProvider).error(errorMessage);
      }
    } catch (_) {
      if (context.mounted) {
        ref.read(noticeServiceProvider).error(errorMessage);
      }
    }
  }
}

class _EmailOption {
  const _EmailOption({
    required this.label,
    required this.icon,
    required this.uri,
  });
  final String label;
  final IconData icon;
  final Uri uri;
}
