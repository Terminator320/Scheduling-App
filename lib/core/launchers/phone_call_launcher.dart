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
  await launchExternalUri(
    context,
    ref,
    dialableUri(phone),
    tag: 'LAUNCH-TEL',
    errorMessage: context.l10n.error_couldNotStartCall,
  );
}

/// The `tel:` URI for a STORED phone number.
///
/// Numbers are stored formatted — "(514) 555-1234" — and `Uri` percent-encodes
/// the brackets and space into a path some dialers reject. Strip to digits,
/// keeping a leading `+` so international numbers still dial, and fall back to
/// the raw text when there is nothing to strip (an extension-only or
/// alphabetic entry is still better handed over than dropped).
///
/// Pure so the stripping rule can be pinned without a plugin.
Uri dialableUri(String phone) {
  final trimmed = phone.trim();
  final dialable = trimmed.startsWith('+')
      ? '+${phoneDigits(trimmed)}'
      : phoneDigits(trimmed);
  return Uri(scheme: 'tel', path: dialable.isEmpty ? trimmed : dialable);
}
