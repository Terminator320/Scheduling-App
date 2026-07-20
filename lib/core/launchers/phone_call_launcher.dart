import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the device dialer for [phone]. Surfaces an error notice when the
/// dialer can't be launched. Shared by the client and appointment detail views.
Future<void> launchPhoneCall(
  BuildContext context,
  WidgetRef ref,
  String phone,
) async {
  final uri = Uri(scheme: 'tel', path: phone.trim());
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_couldNotStartCall);
    }
  } catch (e, st) {
    // Logged before the mounted guard — a thrown launchUrl usually means a
    // malformed tel: URI or a missing Android <queries> entry, which is
    // otherwise invisible until a user reports a dead Call button.
    ref.read(loggerProvider).warn('LAUNCH-TEL launchUrl failed', e, st);
    if (context.mounted) {
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_couldNotStartCall);
    }
  }
}
