import 'dart:io';
import 'package:flutter/material.dart';

class ImageViewer extends StatefulWidget {
  final List<ImageProvider> images;
  final int initialIndex;

  const ImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

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
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) =>
            ImageViewer(images: images, initialIndex: initialIndex),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
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
    // Backdrop is always the dark scrim, so foreground stays light in both
    // light and dark themes.
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
                      errorBuilder: (_, __, ___) => Icon(
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
                  icon: Icon(Icons.close, color: foreground),
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
    ...urls.map<ImageProvider>((u) => NetworkImage(u)),
    ...files.map<ImageProvider>((f) => FileImage(f)),
  ];
}
