import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// The app's standard back arrow: an [IconButton] that nudges left and
/// springs back on press. Reused by `AppTopBar` and any other back-control
/// screen, so the feedback stays consistent everywhere. The press animation
/// collapses to instant under reduced motion.
class AppBackButton extends StatefulWidget {
  const AppBackButton({required this.onTap, this.tooltip, super.key});

  final VoidCallback onTap;

  /// Defaults to the platform "Back" tooltip/semantics when omitted.
  final String? tooltip;

  @override
  State<AppBackButton> createState() => _AppBackButtonState();
}

class _AppBackButtonState extends State<AppBackButton> {
  final WidgetStatesController _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStatesChanged);
  }

  void _onStatesChanged() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  void dispose() {
    _states
      ..removeListener(_onStatesChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final active = _pressed && !reduceMotion;
    final tooltip =
        widget.tooltip ?? MaterialLocalizations.of(context).backButtonTooltip;
    // Quick ease-in while pressed, slower spring back on release.
    final duration = _pressed ? AppDuration.fast : AppDuration.normal;
    final curve = _pressed ? Curves.easeOut : Curves.elasticOut;
    return IconButton(
      statesController: _states,
      tooltip: tooltip,
      onPressed: widget.onTap,
      icon: AnimatedSlide(
        offset: active ? const Offset(-0.22, 0) : Offset.zero,
        duration: duration,
        curve: curve,
        child: AnimatedScale(
          scale: active ? 0.72 : 1,
          duration: duration,
          curve: curve,
          child: Icon(
            context.isCupertino
                ? Icons.arrow_back_ios_new
                : Icons.arrow_back_rounded,
          ),
        ),
      ),
    );
  }
}
