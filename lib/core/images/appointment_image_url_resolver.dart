import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

/// App-wide resolver, injectable so widget tests never touch Storage.
final appointmentImageUrlResolverProvider =
    Provider<AppointmentImageUrlResolver>(
      (ref) => AppointmentImageUrlResolver(logger: ref.watch(loggerProvider)),
    );

/// Turns an appointment photo's `storagePath` into a URL to render.
///
/// **Photos are deliberately NOT rendered from the `url` persisted at upload
/// time.** `getDownloadURL()` mints a permanent `?alt=media&token=…` URL that
/// anyone holding it can read with no auth and no rules evaluation, so a URL
/// captured while an employee was active kept working after
/// `deactivateEmployee` disabled their Auth account and revoked their tokens —
/// which is precisely what `storage.rules`' `status == 'active'` gate on
/// appointment images exists to prevent. Asking Storage for the URL at render
/// time puts a rules check in front of every photo the device does not already
/// have.
///
/// The token itself is stable per object, so the resolved URL is stable too
/// and `cached_network_image` keeps caching the bytes as before.
///
/// A doc written before `storagePath` was stored falls back to its `url` —
/// there is nothing else to render it from. That fallback is why this is not
/// a migration.
class AppointmentImageUrlResolver {
  AppointmentImageUrlResolver({FirebaseStorage? storage, AppLogger? logger})
    : _storage = storage ?? FirebaseStorage.instance,
      _logger = logger ?? AppLogger();

  final FirebaseStorage _storage;
  final AppLogger _logger;

  Future<String> resolve(AppointmentImage image) async {
    if (image.storagePath.isEmpty) return image.url;
    try {
      return await _storage.ref(image.storagePath).getDownloadURL();
    } catch (e, st) {
      _logger.warn('IMG-URL resolve failed: ${image.storagePath}', e, st);
      // A RULES REJECTION MUST NOT FALL BACK. The stored url is the permanent
      // token URL described above — it reads with no auth and no rules
      // evaluation — so returning it here would hand back a working, rules-free
      // link in exactly the case this class exists to refuse. Everything else
      // (offline, a transient Storage failure) keeps the fallback, which is
      // strictly better than a broken tile for someone who IS entitled.
      if (_isPermissionDenied(e)) return '';
      return image.url;
    }
  }

  static bool _isPermissionDenied(Object error) {
    if (error is! FirebaseException) return false;
    return error.code == 'unauthorized' || error.code == 'permission-denied';
  }

  /// Resolves in list order so the returned URLs line up index-for-index with
  /// [images] — the viewer opens at a tapped index, so a reordered result
  /// would open the wrong photo.
  Future<List<String>> resolveAll(List<AppointmentImage> images) =>
      Future.wait(images.map(resolve));
}
