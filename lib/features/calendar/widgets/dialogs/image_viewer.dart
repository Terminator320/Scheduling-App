import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/permissions/media_permission_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:share_plus/share_plus.dart';

class ImageViewer extends ConsumerStatefulWidget {
  const ImageViewer({required this.images, super.key, this.initialIndex = 0});
  final List<ImageProvider> images;
  final int initialIndex;

  static Future<void> open(
    BuildContext context, {
    required List<ImageProvider> images,
    int initialIndex = 0,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: scheme.scrim.withValues(alpha: 0.87),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            ImageViewer(images: images, initialIndex: initialIndex),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  ConsumerState<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<ImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  /// Shared by every page's [InteractiveViewer]; drives [_zoomed] to route drags to zoom or dismiss.
  final _transformController = TransformationController();
  bool _zoomed = false;

  /// Current vertical drag displacement of the image, in logical pixels.
  double _dragOffset = 0;

  /// True while save/share is resolving; disables actions to prevent double-launch.
  bool _busy = false;

  /// Anchors the iPad share-sheet popover to the share button's frame.
  final GlobalKey _shareButtonKey = GlobalKey();

  /// Downward displacement past which releasing the drag dismisses the viewer.
  static const double _dismissDistance = 120;

  /// Downward fling velocity (px/s) that dismisses regardless of distance.
  static const double _dismissVelocity = 700;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    final flungDown = details.velocity.pixelsPerSecond.dy > _dismissVelocity;
    if (_dragOffset > _dismissDistance || flungDown) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragOffset = 0);
  }

  void _onDragCancel() {
    setState(() => _dragOffset = 0);
  }

  /// Resolves the on-screen image to an on-disk file that share/save need:
  /// local picks already are files; network images resolve to their cached
  /// copy, downloading once if evicted.
  Future<File?> _currentImageFile() async {
    final provider = widget.images[_currentIndex];
    if (provider is FileImage) return provider.file;
    if (provider is CachedNetworkImageProvider) {
      return DefaultCacheManager().getSingleFile(provider.url);
    }
    return null;
  }

  /// Runs [body] under the shared `_busy` guard (so a double-tap can't launch
  /// two saves/shares), logging under [logTag] and showing [errorMessage] on
  /// throw.
  Future<void> _runExclusive(
    String logTag,
    String errorMessage,
    Future<void> Function() body,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } catch (e, st) {
      ref.read(loggerProvider).warn('$logTag failed', e, st);
      if (!mounted) return;
      ref.read(noticeServiceProvider).error(errorMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToPhotos() => _runExclusive(
    'IMG-SAVE',
    context.l10n.calendar_couldNotSavePhoto,
    () async {
      // iOS gates on add-only Photos access; saver_gallery would fail silently
      // without it. Android (dev-only) handles its own permission natively.
      if (Platform.isIOS) {
        final perm = await ref
            .read(mediaPermissionServiceProvider)
            .ensurePhotoAddOnly();
        if (!mounted) return;
        if (perm != MediaPermissionResult.granted) {
          ref
              .read(noticeServiceProvider)
              .error(context.l10n.calendar_photoLibraryAccessNeeded);
          return;
        }
      }
      final file = await _currentImageFile();
      if (file == null) throw StateError('image source not resolvable');
      final result = await SaverGallery.saveFile(
        filePath: file.path,
        fileName: 'ESPro_${DateTime.now().millisecondsSinceEpoch}.jpg',
        skipIfExists: false,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.calendar_photoSavedToPhotos);
      } else {
        ref
            .read(loggerProvider)
            .warn('IMG-SAVE saver_gallery: ${result.errorMessage}');
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.calendar_couldNotSavePhoto);
      }
    },
  );

  Future<void> _share() => _runExclusive(
    'IMG-SHARE',
    context.l10n.error_somethingWentWrongPleaseTryAgain,
    () async {
      final file = await _currentImageFile();
      if (file == null) throw StateError('image source not resolvable');
      // iPad anchors the share popover to the button's frame, else it throws.
      final box =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const foreground = Colors.white;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final dragFraction = (_dragOffset.abs() / (_dismissDistance * 2)).clamp(
      0.0,
      1.0,
    );

    Widget pager = PageView.builder(
      controller: _pageController,
      itemCount: widget.images.length,
      onPageChanged: (i) {
        _transformController.value = Matrix4.identity();
        setState(() => _currentIndex = i);
      },
      itemBuilder: (context, index) {
        return InteractiveViewer(
          transformationController: _transformController,
          // Single-finger pans belong to drag-down-to-dismiss until the user
          // has pinch-zoomed in; then they pan the zoomed image instead.
          panEnabled: _zoomed,
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image(
              image: widget.images[index],
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: foreground.withValues(alpha: 0.54),
                size: 64,
              ),
            ),
          ),
        );
      },
    );

    // Drag-follow translate + fade; with reduce-motion on, the image stays
    // put and the gesture only pops past the threshold.
    if (!reduceMotion && _dragOffset != 0) {
      pager = Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Opacity(opacity: 1 - (0.6 * dragFraction), child: pager),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            onVerticalDragUpdate: _zoomed ? null : _onDragUpdate,
            onVerticalDragEnd: _zoomed ? null : _onDragEnd,
            onVerticalDragCancel: _zoomed ? null : _onDragCancel,
            child: pager,
          ),
          _ViewerOverlay(
            busy: _busy,
            currentIndex: _currentIndex,
            imageCount: widget.images.length,
            shareButtonKey: _shareButtonKey,
            onSave: _saveToPhotos,
            onShare: _share,
            onClose: () => Navigator.of(context).pop(),
            textTheme: theme.textTheme,
          ),
        ],
      ),
    );
  }
}

/// The three fixed overlays drawn above the pager: save/share (top-left),
/// close (top-right), and the page counter (top-center, multi-image only).
class _ViewerOverlay extends StatelessWidget {
  const _ViewerOverlay({
    required this.busy,
    required this.currentIndex,
    required this.imageCount,
    required this.shareButtonKey,
    required this.onSave,
    required this.onShare,
    required this.onClose,
    required this.textTheme,
  });

  final bool busy;
  final int currentIndex;
  final int imageCount;
  final GlobalKey shareButtonKey;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onClose;
  final TextTheme textTheme;

  static const Color _foreground = Colors.white;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sp8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.l10n.calendar_savePhoto,
                    icon: const Icon(Icons.save_alt, color: _foreground),
                    onPressed: busy ? null : onSave,
                  ),
                  IconButton(
                    key: shareButtonKey,
                    tooltip: context.l10n.common_share,
                    icon: const Icon(Icons.ios_share, color: _foreground),
                    onPressed: busy ? null : onShare,
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sp8),
              child: IconButton(
                tooltip: context.l10n.common_close,
                icon: const Icon(Icons.close, color: _foreground),
                onPressed: onClose,
              ),
            ),
          ),
        ),
        if (imageCount > 1)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sp12),
                child: Text(
                  '${currentIndex + 1} / $imageCount',
                  style: textTheme.bodyMedium?.copyWith(color: _foreground),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

List<ImageProvider> buildImageProviders({
  required List<String> urls,
  required List<File> files,
}) {
  return [
    ...urls.map<ImageProvider>(CachedNetworkImageProvider.new),
    ...files.map<ImageProvider>(FileImage.new),
  ];
}
