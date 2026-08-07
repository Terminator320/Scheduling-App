import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/image_viewer.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

/// Swipeable read-only gallery of appointment photos with page-dot indicator.
class AppointmentImageCarousel extends StatefulWidget {
  const AppointmentImageCarousel({required this.images, super.key});

  final List<ImageProvider> images;

  @override
  State<AppointmentImageCarousel> createState() =>
      _AppointmentImageCarouselState();
}

class _AppointmentImageCarouselState extends State<AppointmentImageCarousel> {
  final PageController _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheHeight = (200 * dpr).round();
    // Bound decoded width to on-screen strip width to avoid over-decoding wide images.
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r12),
          child: SizedBox(
            height: 200,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => ImageViewer.open(
                  context,
                  images: widget.images,
                  initialIndex: index,
                ),
                child: Image(
                  image: ResizeImage(
                    widget.images[index],
                    width: cacheWidth,
                    height: cacheHeight,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: AppSpacing.sp8),
          SmoothPageIndicator(
            controller: _controller,
            count: widget.images.length,
            effect: WormEffect(
              dotHeight: 8,
              dotWidth: 8,
              activeDotColor: scheme.primary,
              dotColor: scheme.outlineVariant,
            ),
          ),
        ],
      ],
    );
  }
}
