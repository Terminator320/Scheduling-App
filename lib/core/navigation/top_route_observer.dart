import 'package:flutter/widgets.dart';

/// Records the name of the navigator's topmost route.
///
/// The deep-link dispatcher polls this before pushing the invite screen: on a
/// cold start `SplashScreen` routes with `pushReplacementNamed`, which replaces
/// the **topmost** route, so pushing too early would have splash replace the
/// invite screen itself.
///
/// `didRemove` is deliberately not overridden — `pushNamedAndRemoveUntil`
/// pushes first and then removes, so reacting to the removals would overwrite
/// the just-pushed name with a route that is no longer on the stack.
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
}
