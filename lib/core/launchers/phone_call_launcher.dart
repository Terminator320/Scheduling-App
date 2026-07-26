import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/external_uri_launcher.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Opens the device dialer for [phone], surfacing an error notice if it
/// can't launch. Shared by the client and appointment detail views.
Future<void> launchPhoneCall(
  BuildContext context,
  WidgetRef ref,
  String phone,
) async {
  await launchExternalUri(
    context,
    ref,
    Uri(scheme: 'tel', path: phone.trim()),
    tag: 'LAUNCH-TEL',
    errorMessage: context.l10n.error_couldNotStartCall,
  );
}
