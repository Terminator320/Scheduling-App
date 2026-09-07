import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/permissions/media_permission_service.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Prompts the user to pick a capture source and returns the picked files.
/// Gallery goes straight to the OS picker; camera is gated behind a permission check first.
Future<List<File>> pickAppointmentImages(
  BuildContext context,
  WidgetRef ref,
) async {
  final source = await _showSourceSheet(context);
  if (source == null || !context.mounted) return const [];

  final picker = ref.read(imagePickerProvider);
  if (source == ImageSource.gallery) {
    return await picker.pickMultiImages();
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

/// Picks photos and hands them to [addImages], saying so when the per-job cap
/// dropped any.
///
/// The pick is the longest await in the app — an OS action sheet and then the
/// camera or Photos picker — so the form can be gone by the time it returns.
/// Both form hosts spelled this out, and had already drifted on which
/// `mounted` they checked.
Future<void> pickAndAddAppointmentImages(
  BuildContext context,
  WidgetRef ref, {
  required int Function(List<File>) addImages,
  required int Function() remainingSlots,
}) async {
  final notices = ref.read(noticeServiceProvider);
  final l10n = context.l10n;
  final picked = await pickAppointmentImages(context, ref);
  if (!context.mounted || picked.isEmpty) return;
  // Read AFTER the pick, and it is the room LEFT, never the total cap: the
  // notice only fires when the job is at or near its limit, which is exactly
  // when "only 10 more can be added" is the wrong sentence.
  final room = remainingSlots();
  final dropped = addImages(picked);
  if (dropped > 0) {
    notices.info(
      room == 0
          ? l10n.calendar_photosLimitFull
          : l10n.calendar_photosLimitReached(room),
    );
  }
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
