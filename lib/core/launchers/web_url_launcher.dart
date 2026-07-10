import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the external browser. Surfaces an error notice when the URL
/// is malformed or no handler can open it. Shared launcher for web links
/// (e.g. the privacy policy tile in Settings).
Future<void> launchWebUrl(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    ref.read(noticeServiceProvider).error(context.l10n.error_couldNotOpenLink);
    return;
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_couldNotOpenLink);
    }
  } catch (_) {
    if (context.mounted) {
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_couldNotOpenLink);
    }
  }
}
