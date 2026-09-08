import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scheduling/core/logging/app_logger.dart';

/// Outcome of a media-permission request.
enum MediaPermissionResult { granted, denied, permanentlyDenied }

/// Wraps runtime permission checks for media capture. Only the camera is
/// gated — the gallery goes through the OS picker instead.
class MediaPermissionService {
  MediaPermissionService({
    Future<PermissionStatus> Function()? requestCamera,
    Future<PermissionStatus> Function()? requestPhotoAddOnly,
    AppLogger? logger,
  }) : _requestCamera = requestCamera ?? Permission.camera.request,
       _requestPhotoAddOnly =
           requestPhotoAddOnly ?? Permission.photosAddOnly.request,
       _logger = logger ?? AppLogger();

  final Future<PermissionStatus> Function() _requestCamera;
  final Future<PermissionStatus> Function() _requestPhotoAddOnly;
  final AppLogger _logger;

  Future<MediaPermissionResult> ensureCamera() async {
    try {
      final status = await _requestCamera();
      return _map(status);
    } catch (e, st) {
      _logger.warn('PERM-MEDIA ensureCamera failed', e, st);
      return MediaPermissionResult.denied;
    }
  }

  /// Add-only photo-library access for saving appointment photos to the device
  /// gallery.
  Future<MediaPermissionResult> ensurePhotoAddOnly() async {
    try {
      final status = await _requestPhotoAddOnly();
      return _map(status);
    } catch (e, st) {
      _logger.warn('PERM-MEDIA ensurePhotoAddOnly failed', e, st);
      return MediaPermissionResult.denied;
    }
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
