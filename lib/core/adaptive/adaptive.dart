import 'package:flutter/material.dart';

/// iOS-only adaptive layer. [isCupertino] is the single source of truth for
/// whether the UI should render its Cupertino (iOS/macOS) variant. Reads
/// `Theme.of(context).platform` (not `defaultTargetPlatform`) so widget tests
/// can force either look via `ThemeData(platform: ...)`. Mirrors the
/// `context.isWide` extension convention in `core/layout/breakpoints.dart`.
extension AdaptivePlatform on BuildContext {
  bool get isCupertino {
    final platform = Theme.of(this).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }
}
