import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/images/appointment_image_url_resolver.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/image_viewer.dart';
import 'package:scheduling/features/calendar/widgets/views/appointment_image_carousel.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

/// The appointment photo strip / carousel.
///
/// Stateful only because the existing photos' display URLs are resolved from
/// their `storagePath` at render time rather than read off the record — see
/// [AppointmentImageUrlResolver] for why the persisted URL is not used.
class PhotoPickerSection extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<PhotoPickerSection> createState() => _PhotoPickerSectionState();
}

class _PhotoPickerSectionState extends ConsumerState<PhotoPickerSection> {
  List<String> _resolvedUrls = const [];

  /// The exact list [_resolvedUrls] was resolved for. The URLs are positional,
  /// so they are only meaningful against this list — after a removal the
  /// widget rebuilds with a shorter `existingImages` while the old URLs are
  /// still in hand, and index 0 would render the photo just deleted.
  List<AppointmentImage> _resolvedFor = const [];

  /// The existing photos' URLs, or empty while a resolve is outstanding.
  ///
  /// Empty rather than partial on purpose: every consumer indexes it
  /// positionally beside `newImages`, so a short list silently shifts the new
  /// photos' indices. Empty renders placeholders and is unambiguous.
  List<String> get _existingUrls =>
      listEquals(_resolvedFor, widget.existingImages)
      ? _resolvedUrls
      : const [];

  @override
  void initState() {
    super.initState();
    _resolveUrls();
  }

  @override
  void didUpdateWidget(PhotoPickerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.existingImages, widget.existingImages)) {
      _resolveUrls();
    }
  }

  Future<void> _resolveUrls() async {
    final images = widget.existingImages;
    if (images.isEmpty) {
      if (_resolvedUrls.isNotEmpty) {
        setState(() {
          _resolvedUrls = const [];
          _resolvedFor = const [];
        });
      }
      return;
    }
    final urls = await ref
        .read(appointmentImageUrlResolverProvider)
        .resolveAll(images);
    // The resolve outlives a fast edit-and-close, and the sheet is disposed
    // under it more often than not.
    if (!mounted || !listEquals(images, widget.existingImages)) return;
    setState(() {
      _resolvedUrls = urls;
      _resolvedFor = images;
    });
  }

  void _openViewer(BuildContext context, int tappedIndex) {
    final providers = buildImageProviders(
      urls: _existingUrls,
      files: widget.newImages,
    );
    if (providers.isEmpty) return;
    ImageViewer.open(context, images: providers, initialIndex: tappedIndex);
  }

  // A read-only swipeable carousel. Returns an empty box when there are no real images, so the failure banner can stand alone.
  Widget _readOnlyGallery() {
    final providers = buildImageProviders(
      urls: _existingUrls,
      files: widget.newImages,
    );
    if (providers.isEmpty) return const SizedBox.shrink();
    return AppointmentImageCarousel(images: providers);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhotos =
        widget.existingImages.isNotEmpty ||
        widget.newImages.isNotEmpty ||
        widget.failedCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPhotos && !widget.isEditing)
          _readOnlyGallery()
        else if (hasPhotos)
          _EditablePhotoStrip(
            existingImages: widget.existingImages,
            existingUrls: _existingUrls,
            newImages: widget.newImages,
            failedCount: widget.failedCount,
            onOpenViewer: _openViewer,
            onRemoveExisting: widget.onRemoveExisting,
            onRemoveNew: widget.onRemoveNew,
            onPickImages: widget.onPickImages,
          )
        else if (widget.isEditing)
          _EditableEmptyPhotoState(onPickImages: widget.onPickImages)
        else
          const _ReadOnlyEmptyPhotoState(),

        if (widget.failedCount > 0) ...[
          const SizedBox(height: AppSpacing.sp8),
          _UploadFailedRow(count: widget.failedCount, onRetry: widget.onRetry),
        ],

        for (final name in widget.tooLargeFileNames) ...[
          const SizedBox(height: AppSpacing.sp8),
          _TooLargeBanner(fileName: name),
        ],
      ],
    );
  }
}

class _EditablePhotoStrip extends StatelessWidget {
  const _EditablePhotoStrip({
    required this.existingImages,
    required this.existingUrls,
    required this.newImages,
    required this.failedCount,
    required this.onOpenViewer,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    required this.onPickImages,
  });

  final List<AppointmentImage> existingImages;
  final List<String> existingUrls;
  final List<File> newImages;
  final int failedCount;
  final void Function(BuildContext context, int tappedIndex) onOpenViewer;
  final void Function(int index) onRemoveExisting;
  final void Function(int index) onRemoveNew;
  final VoidCallback onPickImages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final thumbCache = (90 * MediaQuery.devicePixelRatioOf(context)).round();

    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...existingImages.asMap().entries.map(
            (entry) => _existingThumb(context, entry, thumbCache),
          ),
          ...newImages.asMap().entries.map(
            (entry) => _newThumb(context, entry, thumbCache),
          ),
          ...List.generate(
            failedCount,
            (_) => const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sp8),
              child: _FailedPhotoThumb(),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPickImages,
              borderRadius: BorderRadius.circular(AppRadius.r8),
              child: Ink(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: scheme.onSurfaceVariant),
                    Text(
                      context.l10n.calendar_addMore,
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _existingThumb(
    BuildContext context,
    MapEntry<int, AppointmentImage> entry,
    int thumbCache,
  ) {
    // Null until the URL has been resolved from storagePath — a placeholder,
    // not an error. It is a Storage round-trip per photo, so this is a real
    // window, not a frame or two: a placeholder must not be tappable, or the
    // tap opens whatever provider happens to sit at this index (a NEW photo,
    // since the viewer is only handed the files until the resolve lands).
    final url = entry.key < existingUrls.length
        ? existingUrls[entry.key]
        : null;
    // An EMPTY resolved url is a rules rejection, not a pending resolve — the
    // resolver refuses to fall back to the rules-free token URL. Show the
    // error tile and keep it untappable rather than fetching nothing.
    final refused = url != null && url.isEmpty;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sp8),
          child: GestureDetector(
            onTap: url == null || refused
                ? null
                : () => onOpenViewer(context, entry.key),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.r8),
              child: refused
                  ? SizedBox(
                      width: 90,
                      height: 90,
                      child: _photoErrorTile(context),
                    )
                  : url == null
                  ? SizedBox(
                      width: 90,
                      height: 90,
                      child: _photoPlaceholder(context),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      width: 90,
                      height: 90,
                      memCacheWidth: thumbCache,
                      memCacheHeight: thumbCache,
                      fit: BoxFit.cover,
                      placeholder: (ctx, _) => _photoPlaceholder(ctx),
                      errorWidget: (ctx, _, _) => _photoErrorTile(ctx),
                    ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 12,
          child: formRemoveButton(
            context,
            onTap: () => onRemoveExisting(entry.key),
          ),
        ),
      ],
    );
  }

  Widget _newThumb(
    BuildContext context,
    MapEntry<int, File> entry,
    int thumbCache,
  ) {
    // Offset by the URLs the viewer will actually be handed, NOT by
    // existingImages: while a resolve is outstanding `existingUrls` is empty,
    // so counting the images would point past the end of the provider list.
    final viewerIndex = existingUrls.length + entry.key;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sp8),
          child: GestureDetector(
            onTap: () => onOpenViewer(context, viewerIndex),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.r8),
              child: Image.file(
                entry.value,
                width: 90,
                height: 90,
                cacheWidth: thumbCache,
                cacheHeight: thumbCache,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 12,
          child: formRemoveButton(
            context,
            onTap: () => onRemoveNew(entry.key),
          ),
        ),
      ],
    );
  }
}

class _EditableEmptyPhotoState extends StatelessWidget {
  const _EditableEmptyPhotoState({required this.onPickImages});

  final VoidCallback onPickImages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onPickImages,
      borderRadius: BorderRadius.circular(AppRadius.r8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp16),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.r8),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.sp4),
              Text(
                context.l10n.calendar_tapToAddPhotos,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyEmptyPhotoState extends StatelessWidget {
  const _ReadOnlyEmptyPhotoState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r8),
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
            const SizedBox(height: AppSpacing.sp4),
            Text(
              context.l10n.calendar_noPhotos,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedPhotoThumb extends StatelessWidget {
  const _FailedPhotoThumb();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.error,
    );
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        border: Border.all(color: scheme.error, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded, size: 22, color: scheme.error),
          const SizedBox(height: AppSpacing.sp4),
          Text(context.l10n.calendar_photoFailedBadge, style: style),
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
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: scheme.error,
          ),
        ),
        const SizedBox(width: AppSpacing.sp4),
        Expanded(
          child: Text(
            context.l10n.calendar_nPhotosFailedToUpload(count),
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.error,
            ),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: AppSpacing.sp8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sp8,
                vertical: AppSpacing.sp4,
              ),
            ),
            child: Text(
              context.l10n.common_retry,
              style: textTheme.labelSmall?.copyWith(
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
    child: AdaptiveProgressIndicator(size: 18, color: scheme.outline),
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
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp12,
        vertical: AppSpacing.sp8,
      ),
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
          const SizedBox(width: AppSpacing.sp8),
          Expanded(
            child: Text(
              context.l10n.calendar_fileTooLargeWarning(fileName),
              style: textTheme.bodySmall?.copyWith(
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
