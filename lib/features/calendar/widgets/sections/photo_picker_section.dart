import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/image_viewer.dart';
import 'package:scheduling/features/calendar/widgets/views/appointment_image_carousel.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

class PhotoPickerSection extends StatelessWidget {
  const PhotoPickerSection({
    required this.existingImages,
    required this.newImages,
    required this.isEditing,
    required this.onPickImages,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    super.key,
    this.failedCount = 0,
    this.tooLargeFileNames = const [],
    this.onRetry,
  });
  final List<AppointmentImage> existingImages;
  final List<File> newImages;
  final bool isEditing;
  final VoidCallback onPickImages;
  final void Function(int index) onRemoveExisting;
  final void Function(int index) onRemoveNew;
  final int failedCount;
  final List<String> tooLargeFileNames;
  final VoidCallback? onRetry;

  void _openViewer(BuildContext context, int tappedIndex) {
    final providers = buildImageProviders(
      urls: existingImages.map((i) => i.url).toList(),
      files: newImages,
    );
    if (providers.isEmpty) return;
    ImageViewer.open(context, images: providers, initialIndex: tappedIndex);
  }

  // Read-only display: a swipeable carousel with page dots. Returns an empty
  // box when there are no real images (e.g. only upload failures), so the
  // failure banner below stands alone.
  Widget _readOnlyGallery() {
    final providers = buildImageProviders(
      urls: existingImages.map((i) => i.url).toList(),
      files: newImages,
    );
    if (providers.isEmpty) return const SizedBox.shrink();
    return AppointmentImageCarousel(images: providers);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhotos =
        existingImages.isNotEmpty || newImages.isNotEmpty || failedCount > 0;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPhotos && !isEditing)
          _readOnlyGallery()
        else if (hasPhotos)
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...existingImages.asMap().entries.map((entry) {
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _openViewer(context, entry.key),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: entry.value.url,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              placeholder: (ctx, _) => _photoPlaceholder(ctx),
                              errorWidget: (ctx, _, _) => _photoErrorTile(ctx),
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
                ...List.generate(
                  failedCount,
                  (_) => const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _FailedPhotoThumb(),
                  ),
                ),
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
                            context.l10n.calendar_addMore,
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
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
                      context.l10n.calendar_tapToAddPhotos,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
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
                  Icon(
                    Icons.photo_library_outlined,
                    color: scheme.onSurfaceVariant,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.calendar_noPhotos,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (failedCount > 0) ...[
          const SizedBox(height: 6),
          _UploadFailedRow(count: failedCount, onRetry: onRetry),
        ],

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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        border: Border.all(color: scheme.error, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded, size: 22, color: scheme.error),
          const SizedBox(height: 4),
          Text(
            context.l10n.calendar_photoFailedBadge,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: scheme.error,
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 13, color: scheme.error),
        const SizedBox(width: 5),
        Text(
          context.l10n.calendar_nPhotosFailedToUpload(count),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.error,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              context.l10n.common_retry,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Widget _photoPlaceholder(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    width: 90,
    height: 90,
    color: scheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(scheme.outline),
      ),
    ),
  );
}

Widget _photoErrorTile(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    width: 90,
    height: 90,
    decoration: BoxDecoration(
      color: scheme.errorContainer.withValues(alpha: 0.3),
      border: Border.all(color: scheme.outlineVariant),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.broken_image_outlined,
      size: 28,
      color: scheme.onErrorContainer,
    ),
  );
}

class _TooLargeBanner extends StatelessWidget {
  const _TooLargeBanner({required this.fileName});
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        border: Border.all(color: scheme.tertiary),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.calendar_fileTooLargeWarning(fileName),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.onTertiaryContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
