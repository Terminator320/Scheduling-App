import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/external_uri_launcher.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Opens a prebuilt Google Maps directions [uri] in the external maps app;
/// errors surface through the notice overlay (never a SnackBar).
Future<void> launchGoogleMapsRoute(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
) async {
  await launchExternalUri(
    context,
    ref,
    uri,
    tag: 'LAUNCH-MAPS',
    errorMessage: context.l10n.error_couldNotOpenMapApp,
  );
}
