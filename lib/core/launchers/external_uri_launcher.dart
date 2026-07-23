import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens uri in an external app with error notice on failure — the single implementation behind launch* helpers to prevent per-copy drift; tag prefixes the logger label for Crashlytics mapping.
Future<bool> launchExternalUri(
  BuildContext context,
  WidgetRef ref,
  Uri uri, {
  required String tag,
  required String errorMessage,
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  try {
    final opened = await launchUrl(uri, mode: mode);
    if (!opened) {
      ref.read(loggerProvider).warn('$tag launchUrl returned false');
      if (context.mounted) {
        ref.read(noticeServiceProvider).error(errorMessage);
      }
    }
    return opened;
  } catch (e, st) {
    ref.read(loggerProvider).warn('$tag launchUrl failed', e, st);
    if (context.mounted) {
      ref.read(noticeServiceProvider).error(errorMessage);
    }
    return false;
  }
}
