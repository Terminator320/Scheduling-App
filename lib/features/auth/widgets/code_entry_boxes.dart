import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/auth/domain/signup_code_policy.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The twelve-character signup code, entered through ONE hidden [TextField]
/// that paints twelve bordered boxes.
///
/// Twelve real fields would mean eleven focus hand-offs, a broken paste and a
/// backspace that has to guess which box it came from; one field owns focus,
/// the keyboard and the clipboard, and the boxes are pure painting. A pasted
/// `XXXX-XXXX-XXXX` lands as twelve clean characters because the input runs
/// through [normalizeSignupCode] before it ever reaches the controller.
class CodeEntryBoxes extends StatefulWidget {
  const CodeEntryBoxes({
    required this.controller,
    required this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.hasError = false,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final bool enabled;

  /// Reddens every box — a bad code is one wrong credential, not one wrong
  /// character, so there is no per-box error state to show.
  final bool hasError;

  @override
  State<CodeEntryBoxes> createState() => _CodeEntryBoxesState();
}

class _CodeEntryBoxesState extends State<CodeEntryBoxes> {
  static const int _groupSize = 4;
  static const double _baseFontSize = 15;

  static final List<TextInputFormatter> _formatters = [
    _SignupCodeInputFormatter(),
  ];

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onStateChanged);
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(CodeEntryBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onStateChanged);
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _focusNode
      ..removeListener(_onStateChanged)
      ..dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    // Only the box the next character lands in carries the ring, and only
    // while the hidden field actually holds focus.
    final activeIndex = _focusNode.hasFocus
        ? math.min(text.length, kSignupCodeLength - 1)
        : -1;

    return Stack(
      children: [
        // Twelve boxes are one logical field, so they carry no semantics of
        // their own — the hidden field below speaks for all of them.
        ExcludeSemantics(child: _boxRow(context, text, activeIndex)),
        Positioned.fill(
          child: Semantics(
            label: context.l10n.auth_signupCodeSemantics(text.length),
            excludeSemantics: true,
            child: _hiddenField(),
          ),
        ),
      ],
    );
  }

  Widget _boxRow(BuildContext context, String text, int activeIndex) {
    final theme = Theme.of(context);
    // Derived from the scaled glyph, never a constant: the boxes have to grow
    // with the user's text size instead of clipping the code.
    final scaled = MediaQuery.textScalerOf(context).scale(_baseFontSize);
    final height = math.max<double>(48, scaled * 2.4);

    return Row(
      children: [
        for (var index = 0; index < kSignupCodeLength; index++) ...[
          if (index > 0)
            SizedBox(
              width: index % _groupSize == 0 ? AppSpacing.sp12 : AppSpacing.sp4,
            ),
          Expanded(
            child: _box(
              theme,
              height: height,
              character: index < text.length ? text[index] : '',
              isActive: index == activeIndex,
            ),
          ),
        ],
      ],
    );
  }

  Widget _box(
    ThemeData theme, {
    required double height,
    required String character,
    required bool isActive,
  }) {
    final scheme = theme.colorScheme;
    final borderColor = widget.hasError
        ? scheme.error
        : isActive
        ? scheme.primary
        : scheme.outlineVariant;

    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r8),
        border: Border.all(color: borderColor, width: isActive ? 2 : 1),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(character, style: theme.monoType.metric),
      ),
    );
  }

  Widget _hiddenField() {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      // Kills the predictive/suggestion bar that would otherwise sit over the
      // boxes offering dictionary words for a random code.
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      inputFormatters: _formatters,
      // The field itself is invisible and stretched over the boxes so a tap
      // anywhere in the row focuses it and a long-press can still paste.
      style: const TextStyle(color: Colors.transparent, fontSize: 1, height: 1),
      cursorColor: Colors.transparent,
      showCursor: false,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
    );
  }
}

/// Normalizes then caps in one pass. Order matters: capping first would
/// truncate `XXXX-XXXX-XXXX` mid-code and normalizing the remains yields ten
/// characters, not twelve.
class _SignupCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = normalizeSignupCode(newValue.text);
    final capped = normalized.length > kSignupCodeLength
        ? normalized.substring(0, kSignupCodeLength)
        : normalized;
    return TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }
}
