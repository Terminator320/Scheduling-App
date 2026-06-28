import 'package:flutter/material.dart';

/// The company name, shown as a wordmark on the splash and onboarding welcome.
/// A proper noun — identical in every locale, so it is not localized.
const String brandName = 'Plombier Eau Secours!';

/// The circular plumber-mascot brand mark (`assets/images/icon.png`), the same
/// image the OS native splash and launcher icon use. Reads well on both the
/// light/dark app surface and the brand-blue splash. Defaults to 72 logical
/// pixels; callers size it for their context (auth header vs. splash hero).
///
/// Falls back to a neutral brand-tinted glyph if the asset can't be decoded
/// (e.g. in the widget-test bundle) so a missing image never throws.
///
/// Set [decorative] when a visible brand wordmark sits right beside the mark
/// (splash, onboarding bar) so a screen reader doesn't announce the name twice;
/// the auth header leaves it on, where the mark is the only brand cue.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 72, this.decorative = false, super.key});

  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    // Decode near the display size rather than the asset's full resolution —
    // the mark renders as small as 32px (onboarding bar) and up to 156px.
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final image = Image.asset(
      'assets/images/icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
      errorBuilder: (context, error, stackTrace) => _Fallback(size: size),
    );
    if (decorative) return ExcludeSemantics(child: image);
    return Semantics(label: brandName, image: true, child: image);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.plumbing_rounded,
        size: size * 0.5,
        color: scheme.primary,
      ),
    );
  }
}
