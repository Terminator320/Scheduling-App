import 'dart:io' show Platform;

/// Whether this device is the one platform the app ships on.
///
/// A SEAM, not a wrapper for its own sake. `flutter test` runs on the host, so
/// a bare `Platform.isIOS` gate returns before any injectable point and leaves
/// everything behind it unreachable from the harness — on the only platform
/// that ships. Inject this as a `bool Function()` wherever such a gate guards
/// real logic, and let it default here.
///
/// It lives in `core/` rather than beside its first caller because two of them
/// (`AppSyncListeners` and `LiveActivityRegistrationController`) already import
/// each other; a default parked in either would have closed that cycle.
bool defaultIsIosPlatform() => Platform.isIOS;
