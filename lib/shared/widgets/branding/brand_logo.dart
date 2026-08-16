import 'package:flutter/material.dart';

/// Company wordmark shown on splash/onboarding. It's a proper noun, so it's
/// never localized.
const String brandName = 'Plombier Eau Secours!';

/// Brand mark that falls back to a glyph if the asset is missing. Set
/// [decorative] to true when a wordmark is already visible nearby.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 72, this.decorative = false, super.key});

  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    // Cache decode near display size to avoid over-loading.
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final image = Image.asset(
      // The 512px derivative — see `pubspec.yaml`. `icon.png` is the 1254px
      // master and is deliberately NOT bundled.
      'assets/images/brand_mark.png',
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
