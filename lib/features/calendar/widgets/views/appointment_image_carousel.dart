import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/image_viewer.dart';
import 'package:scheduling/l10n/l10n.dart';
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
              itemBuilder: (context, index) {
                final image = widget.images[index];
                // A refused photo is a transparent 1x1, which renders as a
                // BLANK page — indistinguishable from an empty one. The
                // editable strip already draws an error tile for the same
                // state; this is the read-only half agreeing with it. Not
                // tappable, for the same reason it is not there.
                if (isRefusedImage(image)) return const _RefusedSlide();
                return GestureDetector(
                  onTap: () => ImageViewer.open(
                    context,
                    images: widget.images,
                    initialIndex: index,
                  ),
                  child: Image(
                    image: ResizeImage(
                      image,
                      width: cacheWidth,
                      height: cacheHeight,
                      policy: ResizeImagePolicy.fit,
                    ),
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                );
              },
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

/// What the carousel shows in place of a photo Storage refused.
///
/// Deliberately the same vocabulary as the editable strip's error tile —
/// muted error ground, broken-image glyph — so the two surfaces do not
/// describe the same failure two different ways.
class _RefusedSlide extends StatelessWidget {
  const _RefusedSlide();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.errorContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 32,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(height: AppSpacing.sp8),
          Text(
            context.l10n.calendar_photoUnavailable,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
