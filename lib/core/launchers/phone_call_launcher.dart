import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/external_uri_launcher.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Opens the device dialer for [phone], surfacing an error notice if it
/// can't launch. Shared by the client and appointment detail views.
Future<void> launchPhoneCall(
  BuildContext context,
  WidgetRef ref,
  String phone,
) async {
  // Numbers are stored formatted — "(514) 555-1234" — and Uri percent-encodes
  // the brackets and space into a tel: path some dialers reject. Strip to
  // digits, keeping a leading + so international numbers still dial.
  final trimmed = phone.trim();
  final dialable = trimmed.startsWith('+')
      ? '+${phoneDigits(trimmed)}'
      : phoneDigits(trimmed);

  await launchExternalUri(
    context,
    ref,
    Uri(scheme: 'tel', path: dialable.isEmpty ? trimmed : dialable),
    tag: 'LAUNCH-TEL',
    errorMessage: context.l10n.error_couldNotStartCall,
  );
}
