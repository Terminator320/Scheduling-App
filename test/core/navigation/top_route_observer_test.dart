import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/top_route_observer.dart';

Route<void> _route(String name) => MaterialPageRoute<void>(
  settings: RouteSettings(name: name),
  builder: (_) => const SizedBox.shrink(),
);

void main() {
  late TopRouteObserver observer;

  setUp(() => observer = TopRouteObserver());

  test('starts with no route name', () {
    expect(observer.currentRouteName, isNull);
  });

  test('a push becomes the current route', () {
    observer.didPush(_route('/login'), null);

    expect(observer.currentRouteName, '/login');
  });

  test('a pop falls back to the route beneath', () {
    observer
      ..didPush(_route('/login'), null)
      ..didPush(_route('/settings'), _route('/login'))
      ..didPop(_route('/settings'), _route('/login'));

    expect(observer.currentRouteName, '/login');
  });

  test('a replace reports the new route, which is how splash routes', () {
    observer
      ..didPush(_route('/splash'), null)
      ..didReplace(newRoute: _route('/login'), oldRoute: _route('/splash'));

    expect(observer.currentRouteName, '/login');
  });

  test('a push over a replace keeps the topmost name', () {
    observer
      ..didReplace(newRoute: _route('/login'), oldRoute: _route('/splash'))
      ..didPush(_route('/forgot-password'), _route('/login'));

    expect(observer.currentRouteName, '/forgot-password');
  });

  test('removing the current top route falls back to the route beneath', () {
    // The hub's redirect shim calls removeRoute(this) on ITSELF after its
    // post-frame handoff, so the same Route instance is pushed and removed.
    final calendar = _route('/calendar');
    final shim = _route('/hub-redirect');
    observer
      ..didPush(calendar, null)
      ..didPush(shim, calendar)
      ..didRemove(shim, calendar);

    expect(observer.currentRouteName, '/calendar');
  });

  test('removing a lower route does not overwrite the current top route', () {
    final calendar = _route('/calendar');
    observer
      ..didPush(calendar, null)
      ..didPush(_route('/settings'), calendar)
      ..didRemove(calendar, null);

    expect(observer.currentRouteName, '/settings');
  });

  test(
    'pushNamedAndRemoveUntil keeps the just-pushed name even when a removed '
    'route shares it',
    () {
      // B4: the guard used to compare NAMES, so removing an older route with
      // the same name as the new top overwrote the top with whatever sat under
      // the removed one. pushNamedAndRemoveUntil pushes BEFORE it removes.
      final oldLogin = _route('/login');
      final calendar = _route('/calendar');
      final newLogin = _route('/login');
      observer
        ..didPush(oldLogin, null)
        ..didPush(calendar, oldLogin)
        // Account disabled: push /login, then unwind everything beneath it.
        ..didPush(newLogin, calendar)
        ..didRemove(calendar, oldLogin)
        ..didRemove(oldLogin, null);

      expect(observer.currentRouteName, '/login');
    },
  );
}
