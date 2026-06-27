import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/l10n/l10n.dart';

class ImageViewer extends StatefulWidget {
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
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const foreground = Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, index) {
                return InteractiveViewer(
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
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: context.l10n.common_close,
                  icon: const Icon(Icons.close, color: foreground),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          if (widget.images.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.images.length}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
