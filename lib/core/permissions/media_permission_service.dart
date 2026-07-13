import 'dart:io';

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
    if (status.isGranted || status.isLimited) {
      return MediaPermissionResult.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MediaPermissionResult.permanentlyDenied;
    }
    return MediaPermissionResult.denied;
  }

  /// Microphone + (iOS-only) speech recognition, gated for dictation.
  Future<MediaPermissionResult> ensureMicrophone() async {
    final results = <PermissionStatus>[await Permission.microphone.request()];
    if (Platform.isIOS) {
      results.add(await Permission.speech.request());
    }
    if (results.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return MediaPermissionResult.permanentlyDenied;
    }
    if (results.every((s) => s.isGranted || s.isLimited)) {
      return MediaPermissionResult.granted;
    }
    return MediaPermissionResult.denied;
  }
}

final mediaPermissionServiceProvider = Provider<MediaPermissionService>(
  (ref) => MediaPermissionService(),
);
