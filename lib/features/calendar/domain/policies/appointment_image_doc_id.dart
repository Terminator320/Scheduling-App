import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

/// Builds the deterministic image document id used by offline retries.
String appointmentImageDocId(AppointmentImage image) =>
    appointmentImageDocIdFor(
      storagePath: image.storagePath,
      url: image.url,
    );

/// Raw-string form for callers that have not parsed an image model.
String appointmentImageDocIdFor({
  required String storagePath,
  required String url,
}) {
  final key = storagePath.trim().isNotEmpty ? storagePath.trim() : url.trim();
  if (key.isEmpty) return '';
  return 'img_${_sanitize(key)}';
}

/// Replaces unsafe Firestore id characters while matching the JS helper.
final _unsafeIdChars = RegExp('[^A-Za-z0-9._-]');

String _sanitize(String key) {
  final sanitized = key.replaceAll(_unsafeIdChars, '_');
  const maxLength = 300;
  return sanitized.length <= maxLength
      ? sanitized
      : sanitized.substring(sanitized.length - maxLength);
}
