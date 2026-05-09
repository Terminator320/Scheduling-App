import 'dart:io';
import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/models/appointment_image.dart';
import 'package:scheduling/features/calendar/widgets/image_viewer.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';

class PhotoPickerSection extends StatelessWidget {
  final List<AppointmentImage> existingImages;
  final List<File> newImages;
  final bool isEditing;
  final VoidCallback onPickImages;
  final void Function(int index) onRemoveExisting;
  final void Function(int index) onRemoveNew;
  final int failedCount;
  final List<String> tooLargeFileNames;
  final VoidCallback? onRetry;

  const PhotoPickerSection({
    super.key,
    required this.existingImages,
    required this.newImages,
    required this.isEditing,
    required this.onPickImages,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    this.failedCount = 0,
    this.tooLargeFileNames = const [],
    this.onRetry,
  });

  void _openViewer(BuildContext context, int tappedIndex) {
    final providers = buildImageProviders(
      urls: existingImages.map((i) => i.url).toList(),
      files: newImages,
    );
    if (providers.isEmpty) return;
    ImageViewer.open(context, images: providers, initialIndex: tappedIndex);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhotos = existingImages.isNotEmpty || newImages.isNotEmpty || failedCount > 0;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPhotos)
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // existing network images
                ...existingImages.asMap().entries.map((entry) {
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _openViewer(context, entry.key),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              entry.value.url,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      if (isEditing)
                        Positioned(
                          top: 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: () => onRemoveExisting(entry.key),
                            child: formRemoveButton(context),
                          ),
                        ),
                    ],
                  );
                }),
                // new local images
                ...newImages.asMap().entries.map((entry) {
                  final viewerIndex = existingImages.length + entry.key;
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _openViewer(context, viewerIndex),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              entry.value,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      if (isEditing)
                        Positioned(
                          top: 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: () => onRemoveNew(entry.key),
                            child: formRemoveButton(context),
                          ),
                        ),
                    ],
                  );
                }),
                // failed upload placeholders
                ...List.generate(failedCount, (_) => const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: _FailedPhotoThumb(),
                )),
                // add more tile (edit mode only)
                if (isEditing)
                  GestureDetector(
                    onTap: onPickImages,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: scheme.onSurfaceVariant),
                          Text(
                            context.l10n.addMore,
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        else if (isEditing)
          InkWell(
            onTap: onPickImages,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.tapToAddPhotos,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, color: scheme.onSurfaceVariant, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.noPhotos,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

        // Inline upload-failure message
        if (failedCount > 0) ...[
          const SizedBox(height: 6),
          _UploadFailedRow(count: failedCount, onRetry: onRetry),
        ],

        // Too-large warning banners
        for (final name in tooLargeFileNames) ...[
          const SizedBox(height: 6),
          _TooLargeBanner(fileName: name),
        ],
      ],
    );
  }
}

class _FailedPhotoThumb extends StatelessWidget {
  const _FailedPhotoThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: AppColors.error, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline_rounded, size: 22, color: AppColors.error),
          const SizedBox(height: 4),
          Text(
            'Failed',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadFailedRow extends StatelessWidget {
  const _UploadFailedRow({required this.count, this.onRetry});
  final int count;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 13, color: AppColors.error),
        const SizedBox(width: 5),
        Text(
          context.l10n.nPhotosFailedToUpload(count),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.error,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              context.l10n.retry,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TooLargeBanner extends StatelessWidget {
  const _TooLargeBanner({required this.fileName});
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        border: Border.all(color: AppColors.warning),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: AppColors.warningText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.fileTooLargeWarning(fileName),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.warningText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
