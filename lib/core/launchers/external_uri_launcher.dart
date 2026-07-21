import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] in an external app, surfacing [errorMessage] as an error notice
/// when the launch reports failure or throws.
///
/// This is the single implementation behind the `launch*` helpers in this
/// directory. They previously each carried their own copy of this body, and the
/// copies drifted — one dropped its `try`/`catch` entirely, so a thrown
/// `launchUrl` escaped to the zone handler as a fatal instead of a notice.
///
/// [tag] prefixes the `logger.warn` label so a user screenshot maps to a
/// Crashlytics line (see `.claude/rules/error-handling.md`). The warn fires
/// BEFORE the `mounted` guard — a thrown `launchUrl` usually means a malformed
/// URI or a missing Android `<queries>` entry, which is otherwise invisible
/// until someone reports a dead button.
///
/// Returns true when the platform reported a successful launch.
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
