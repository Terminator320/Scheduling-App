import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/external_uri_launcher.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Opens [url] in the external browser, surfacing an error notice if it's
/// malformed or no handler can open it (e.g. the privacy policy tile in
/// Settings).
Future<void> launchWebUrl(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final uri = parseWebUrl(url);
  if (uri == null) {
    // Not a catch, but still a user-visible failure - without this it is the
    // one launch path that leaves no Crashlytics trail to match a screenshot
    // against. The URL is a compile-time constant, so it is safe to carry.
    ref.read(loggerProvider).breadcrumb('LAUNCH-URL malformed uri: $url');
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

/// The URL as something worth handing to the OS, or null when it isn't.
///
/// Both a scheme AND an authority are required: `launchUrl` happily accepts a
/// bare "example.com" and then fails at the platform boundary, and a
/// scheme-only value like "https:" opens nothing. These are the Terms and
/// Privacy links that give the consent record its meaning, so the gate is
/// pinned rather than assumed. Restricting this helper to actual web schemes
/// also prevents a bad config value from becoming some other external protocol.
Uri? parseWebUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}
