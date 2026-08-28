import 'package:flutter/material.dart';

/// Provides a private PrimaryScrollController.
class PrimaryScrollScope extends StatefulWidget {
  const PrimaryScrollScope({required this.child, super.key});

  final Widget child;

  @override
  State<PrimaryScrollScope> createState() => _PrimaryScrollScopeState();
}

class _PrimaryScrollScopeState extends State<PrimaryScrollScope> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PrimaryScrollController(controller: _controller, child: widget.child);
}
