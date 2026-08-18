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
      ..didPush(_route('/accept-invite/code'), _route('/login'))
      ..didPop(_route('/accept-invite/code'), _route('/login'));

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
    observer
      ..didPush(_route('/calendar'), null)
      ..didPush(_route('/hub-redirect'), _route('/calendar'))
      ..didRemove(_route('/hub-redirect'), _route('/calendar'));

    expect(observer.currentRouteName, '/calendar');
  });

  test('removing a lower route does not overwrite the current top route', () {
    observer
      ..didPush(_route('/calendar'), null)
      ..didPush(_route('/settings'), _route('/calendar'))
      ..didRemove(_route('/calendar'), null);

    expect(observer.currentRouteName, '/settings');
  });
}
