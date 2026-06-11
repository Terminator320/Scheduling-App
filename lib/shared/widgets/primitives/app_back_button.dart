import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// The app's standard back arrow: an [IconButton] whose icon nudges left and
/// springs back when pressed. Reused by `AppTopBar` and any screen that needs a
/// leading back control, so the chrome and the tap feedback stay consistent.
///
/// The press animation collapses to instant when the platform requests reduced
/// motion (`MediaQuery.disableAnimationsOf`).
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
    // Pressed: quick ease in. Released: slower spring back.
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
          child: const Icon(Icons.arrow_back_rounded),
        ),
      ),
    );
  }
}
