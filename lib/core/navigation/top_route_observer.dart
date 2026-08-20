import 'package:flutter/widgets.dart';

/// Records the name of the navigator's topmost route.
///
/// The deep-link dispatcher polls this before pushing the invite screen: on a
/// cold start `SplashScreen` routes with `pushReplacementNamed`, which replaces
/// the **topmost** route, so pushing too early would have splash replace the
/// invite screen itself.
///
/// `didRemove` only reacts when the removed route IS the current topmost one,
/// and the test is `identical`, never the route's name. `pushNamedAndRemoveUntil`
/// (the account-disabled path) pushes first and then removes the routes beneath,
/// so those removals must be ignored — and a name test does not ignore them
/// when a lower route happens to share the just-pushed route's name, which
/// would leave the observer reporting a route no longer on the stack. The
/// override earns its place because the hub's redirect shim
/// (`hub_shell.dart`) calls `removeRoute(this)` on ITSELF after a post-frame
/// handoff; without handling that, the observer stays stuck on a route that
/// no longer exists.
///
/// Tracking the route object rather than just its name is what makes the
/// identity test possible; `currentRouteName` is derived from it.
class TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? _currentRoute;

  String? get currentRouteName => _currentRoute?.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRoute = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRoute = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _currentRoute = newRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!identical(route, _currentRoute)) return;
    _currentRoute = previousRoute;
  }
}
