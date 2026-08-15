import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One combined terms + location row on its own tinted surface. Unchecked
/// disables the primary button, which is the whole gate.
///
/// "terms of service" inside the sentence is a LINK to the hosted terms page.
/// That is not decoration: ticking this box stamps `termsAcceptedAt`, so the
/// person has to be able to read what they are accepting. If the link ever
/// stops resolving, the consent record stops meaning anything.
///
/// [StatefulWidget] only to own the [TapGestureRecognizer] — a recognizer built
/// in `build` is never disposed and leaks on every rebuild.
class ConsentRow extends StatefulWidget {
  const ConsentRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onTapTerms,
    super.key,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTapTerms;

  @override
  State<ConsentRow> createState() => _ConsentRowState();
}

class _ConsentRowState extends State<ConsentRow> {
  // Reads `widget` at tap time, so it survives a parent rebuild handing down a
  // new callback.
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => widget.onTapTerms();

  @override
  void dispose() {
    _termsTap.dispose();
    super.dispose();
  }

  /// The sentence with its "terms of service" run turned into a link.
  ///
  /// The link text is a separate ARB key that must appear verbatim inside the
  /// sentence. When a translation drifts and it doesn't, this falls back to
  /// one plain span: a missing link is a smaller failure than a consent row
  /// that renders half a sentence, or crashes on a `-1` index.
  InlineSpan _consentSpan(TextStyle? base, ColorScheme scheme) {
    final sentence = context.l10n.auth_termsAndLocationConsent;
    final linkText = context.l10n.auth_termsOfServiceLink;
    final start = sentence.indexOf(linkText);
    if (start < 0) return TextSpan(text: sentence, style: base);

    return TextSpan(
      style: base,
      children: [
        TextSpan(text: sentence.substring(0, start)),
        TextSpan(
          text: linkText,
          style: base?.copyWith(
            color: scheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
          recognizer: _termsTap,
        ),
        TextSpan(text: sentence.substring(start + linkText.length)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The tint rides `tileColor`, not a wrapping DecoratedBox — a ListTile
    // paints onto the nearest Material, so an outer background would swallow
    // its ink splashes (and asserts in debug).
    return CheckboxListTile.adaptive(
      key: const Key('setupConsent'),
      value: widget.value,
      activeColor: scheme.primary,
      tileColor: scheme.primaryContainer,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: AppSpacing.sp4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      // Text.rich, not Text: the link run needs its own recognizer. A tap on
      // that run is claimed by the recognizer rather than the tile, so it
      // opens the terms instead of silently toggling consent — the rest of the
      // row still toggles as before.
      title: Text.rich(
        _consentSpan(
          theme.textTheme.bodySmall?.copyWith(
            color: scheme.onPrimaryContainer,
          ),
          scheme,
        ),
      ),
      onChanged: widget.enabled
          ? (next) => widget.onChanged(next ?? false)
          : null,
    );
  }
}
