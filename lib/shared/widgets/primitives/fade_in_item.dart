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
    // Set up after MediaQuery available; honor reduce-motion.
    if (_didSetup) return;
    _didSetup = true;
    // Only first few rows stagger-fade; rest appear instantly.
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
