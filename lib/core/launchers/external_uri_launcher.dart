import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens uri in an external app, surfacing an error notice on failure. This
/// is the single implementation behind the launch* helpers, so they can't
/// drift out of sync — tag prefixes the logger label for Crashlytics mapping.
Future<bool> launchExternalUri(
  BuildContext context,
  WidgetRef ref,
  Uri uri, {
  required String tag,
  required String errorMessage,
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  // Both resolved before the await. `launchUrl` hands control to the OS, so
  // the caller's widget is frequently gone by the time this resolves — and
  // `ref.read` throws on an unmounted consumer under Riverpod 3, which would
  // replace the launch failure with a StateError and lose the tagged log.
  final logger = ref.read(loggerProvider);
  final notices = ref.read(noticeServiceProvider);
  try {
    final opened = await launchUrl(uri, mode: mode);
    if (!opened) {
      logger.warn('$tag launchUrl returned false');
      if (context.mounted) notices.error(errorMessage);
    }
    return opened;
  } catch (e, st) {
    logger.warn('$tag launchUrl failed', e, st);
    if (context.mounted) notices.error(errorMessage);
    return false;
  }
}
