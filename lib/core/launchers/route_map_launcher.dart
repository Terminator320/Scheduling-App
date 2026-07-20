import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a prebuilt Google Maps directions [uri] in the external maps app.
/// Errors surface through the notice overlay (never a SnackBar).
Future<void> launchGoogleMapsRoute(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_couldNotOpenMapApp);
    }
  } catch (e, st) {
    ref.read(loggerProvider).warn('LAUNCH-MAPS launchUrl failed', e, st);
    if (context.mounted) {
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_couldNotOpenMapApp);
    }
  }
}
