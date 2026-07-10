import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/permissions/media_permission_service.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Prompts for a capture source, enforces the camera permission, and returns
/// the picked files (empty if cancelled or denied).
///
/// Gallery uses the OS photo picker (no permission). Camera is gated through
/// [MediaPermissionService]; a denied grant surfaces a notice instead of
/// silently doing nothing.
Future<List<File>> pickAppointmentImages(
  BuildContext context,
  WidgetRef ref,
) async {
  final source = await _showSourceSheet(context);
  if (source == null || !context.mounted) return const [];

  final picker = ref.read(imagePickerProvider);
  if (source == ImageSource.gallery) {
    return picker.pickMultiImages();
  }

  final result = await ref.read(mediaPermissionServiceProvider).ensureCamera();
  if (result != MediaPermissionResult.granted) {
    if (context.mounted) {
      ref
          .read(noticeServiceProvider)
          .error(
            result == MediaPermissionResult.permanentlyDenied
                ? context.l10n.error_cameraPermissionPermanentlyDenied
                : context.l10n.error_cameraPermissionDenied,
          );
    }
    return const [];
  }

  final file = await picker.pickImage(ImageSource.camera);
  return file == null ? const [] : [file];
}

Future<ImageSource?> _showSourceSheet(BuildContext context) {
  final l = context.l10n;
  return showAdaptiveActionSheet<ImageSource>(
    context,
    actions: [
      AdaptiveSheetAction(
        value: ImageSource.camera,
        label: l.calendar_takePhoto,
        icon: Icons.photo_camera_outlined,
      ),
      AdaptiveSheetAction(
        value: ImageSource.gallery,
        label: l.calendar_chooseFromGallery,
        icon: Icons.photo_library_outlined,
      ),
    ],
  );
}
