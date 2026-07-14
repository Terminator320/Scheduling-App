import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a media-permission request.
enum MediaPermissionResult { granted, denied, permanentlyDenied }

/// Wraps runtime permission checks for media capture. Gallery picking uses the
/// OS photo picker (no permission needed), so only the camera is gated here.
///
/// Injectable for tests; mirrors the optional-dep service pattern.
class MediaPermissionService {
  MediaPermissionService();

  Future<MediaPermissionResult> ensureCamera() async {
    final status = await Permission.camera.request();
    return _map(status);
  }

  /// Add-only photo-library access (iOS `NSPhotoLibraryAddUsageDescription`),
  /// needed to save an appointment photo to the device gallery.
  Future<MediaPermissionResult> ensurePhotoAddOnly() async {
    final status = await Permission.photosAddOnly.request();
    return _map(status);
  }

  MediaPermissionResult _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return MediaPermissionResult.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MediaPermissionResult.permanentlyDenied;
    }
    return MediaPermissionResult.denied;
  }
}

final mediaPermissionServiceProvider = Provider<MediaPermissionService>(
  (ref) => MediaPermissionService(),
);
