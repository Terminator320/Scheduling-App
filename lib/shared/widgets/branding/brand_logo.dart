import 'package:flutter/material.dart';

/// Company wordmark shown on splash/onboarding; a proper noun, never localized.
const String brandName = 'Plombier Eau Secours!';

/// Brand mark; falls back to glyph if asset missing; set decorative when wordmark visible.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 72, this.decorative = false, super.key});

  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    // Cache decode near display size to avoid over-loading.
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
