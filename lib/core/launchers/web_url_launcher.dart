import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/external_uri_launcher.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Opens [url] in the external browser, surfacing an error notice if it's
/// malformed or no handler can open it (e.g. the privacy policy tile in Settings).
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
  await launchExternalUri(
    context,
    ref,
    uri,
    tag: 'LAUNCH-URL',
    errorMessage: context.l10n.error_couldNotOpenLink,
  );
}
