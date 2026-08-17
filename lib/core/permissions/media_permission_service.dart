import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a media-permission request.
enum MediaPermissionResult { granted, denied, permanentlyDenied }

/// Wraps runtime permission checks for media capture. Only the camera is
/// gated — the gallery goes through the OS picker instead.
class MediaPermissionService {
  MediaPermissionService();

  Future<MediaPermissionResult> ensureCamera() async {
    final status = await Permission.camera.request();
    return _map(status);
  }

  /// Add-only photo-library access for saving appointment photos to the device gallery.
  Future<MediaPermissionResult> ensurePhotoAddOnly() async {
    final status = await Permission.photosAddOnly.request();
    return _map(status);
  }

  MediaPermissionResult _map(PermissionStatus status) =>
      mediaPermissionResultOf(status);
}

/// Buckets a raw [PermissionStatus].
///
/// Two of these are easy to get wrong and neither fails loudly: iOS `limited`
/// (the "selected photos" grant) IS usable and must read as granted, and
/// `restricted` (parental controls / MDM) cannot be re-prompted, so it belongs
/// with permanently-denied — asking again would just no-op forever. Pure, so
/// the mapping is testable without the plugin.
MediaPermissionResult mediaPermissionResultOf(PermissionStatus status) {
  if (status.isGranted || status.isLimited) {
    return MediaPermissionResult.granted;
  }
  if (status.isPermanentlyDenied || status.isRestricted) {
    return MediaPermissionResult.permanentlyDenied;
  }
  return MediaPermissionResult.denied;
}

final mediaPermissionServiceProvider = Provider<MediaPermissionService>(
  (ref) => MediaPermissionService(),
);
