import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(sheetContext.l10n.calendar_takePhoto),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(sheetContext.l10n.calendar_chooseFromGallery),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}
