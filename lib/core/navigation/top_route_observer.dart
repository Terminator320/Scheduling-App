import 'package:flutter/widgets.dart';

/// Records the name of the navigator's topmost route.
///
/// The deep-link dispatcher polls this before pushing the invite screen: on a
/// cold start `SplashScreen` routes with `pushReplacementNamed`, which replaces
/// the **topmost** route, so pushing too early would have splash replace the
/// invite screen itself.
///
/// `didRemove` only reacts when the REMOVED route is the current topmost one.
/// `pushNamedAndRemoveUntil` pushes first and then removes lower routes, so
/// those removals must still be ignored — but routes such as the hub's
/// redirect shim remove themselves after a post-frame handoff, and without
/// handling that case the observer stays stuck on a route that no longer
/// exists.
class TopRouteObserver extends NavigatorObserver {
  String? _currentRouteName;

  String? get currentRouteName => _currentRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRouteName = route.settings.name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRouteName = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _currentRouteName = newRoute?.settings.name;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != _currentRouteName) return;
    _currentRouteName = previousRoute?.settings.name;
  }
}
