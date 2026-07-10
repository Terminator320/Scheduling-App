import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

class FadeInItem extends StatefulWidget {
  const FadeInItem({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<FadeInItem> createState() => _FadeInItemState();
}

class _FadeInItemState extends State<FadeInItem>
    with SingleTickerProviderStateMixin {
  static const _maxStagger = 8;
  static const _perItemDelay = Duration(milliseconds: 30);

  AnimationController? _ctrl;
  CurvedAnimation? _opacity;
  bool _didSetup = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs after MediaQuery is available (initState can't read it safely),
    // so we can honour the OS "reduce motion" setting. Set up once.
    if (_didSetup) return;
    _didSetup = true;
    // Only the first few rows stagger-fade. Rows past the window — and every
    // row under reduce-motion — appear instantly, skipping the controller so
    // a long list doesn't allocate (and tear down) one per recycled row.
    if (widget.index >= _maxStagger ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final ctrl = AnimationController(vsync: this, duration: AppDuration.fast);
    _ctrl = ctrl;
    _opacity = CurvedAnimation(parent: ctrl, curve: Curves.easeOut);
    final delay = _perItemDelay * widget.index;
    if (delay == Duration.zero) {
      ctrl.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _opacity?.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _opacity;
    if (opacity == null) return widget.child;
    return FadeTransition(opacity: opacity, child: widget.child);
  }
}
