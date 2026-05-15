import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

class FadeInItem extends StatefulWidget {
  const FadeInItem({
    required this.index,
    required this.child,
    super.key,
  });

  final int index;
  final Widget child;

  @override
  State<FadeInItem> createState() => _FadeInItemState();
}

class _FadeInItemState extends State<FadeInItem>
    with SingleTickerProviderStateMixin {
  static const _maxStagger = 8;
  static const _perItemDelay = Duration(milliseconds: 30);

  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppDuration.fast);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _initAnimation();
  }

  void _initAnimation() {
    final delay = widget.index < _maxStagger
        ? _perItemDelay * widget.index
        : Duration.zero;
    if (delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
