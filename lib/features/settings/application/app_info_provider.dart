import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Resolves the running app's package metadata (version + build number).
///
/// Loaded once on demand for the Settings version footer; `PackageInfo`
/// is immutable for the process lifetime so the keepAlive default is fine.
final appInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});
