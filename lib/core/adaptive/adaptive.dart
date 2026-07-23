import 'package:flutter/material.dart';

/// [isCupertino] is the single source of truth for Cupertino-vs-Material UI,
/// reading `Theme.of(context).platform` (not `defaultTargetPlatform`) so
/// widget tests can force either look via `ThemeData(platform: ...)`.
extension AdaptivePlatform on BuildContext {
  bool get isCupertino {
    final platform = Theme.of(this).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }
}
