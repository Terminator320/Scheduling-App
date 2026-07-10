import 'package:flutter/material.dart';

/// Scopes its subtree under a fresh [PrimaryScrollController].
///
/// A route provides a single [PrimaryScrollController], and on mobile every
/// primary vertical [ScrollView] with no explicit controller attaches to it.
/// When several such scroll views are mounted at once under one route — the
/// hub's [IndexedStack] of always-alive tabs, or a master + detail split — they
/// all attach to that one controller. A [Scrollbar]/`CupertinoScrollbar`
/// (installed app-wide by `AppScrollBehavior`) requires its controller to hold
/// exactly one [ScrollPosition] and throws "attached to more than one
/// ScrollPosition" otherwise. Wrapping each independent scroll surface in its
/// own scope keeps every controller down to a single position — restoring the
/// one-primary-controller-per-screen behavior that separate routes used to give
/// for free.
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
