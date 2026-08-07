import 'package:flutter/material.dart';

/// Scopes a fresh PrimaryScrollController to prevent multiple primary ScrollViews from sharing the same controller and confusing the Scrollbar.
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
