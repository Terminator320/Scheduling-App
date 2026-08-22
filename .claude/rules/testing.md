---
paths:
  - "test/**"
  - "functions/__tests__/**"
---

# Testing

- Verify behavior, not implementation. Don't assert mock call counts when output values would do.
- Run the specific test file after changes, not the full suite. Faster feedback, fewer tokens.
- Flaky test? Fix it or delete it. Never retry to make it pass.
- Prefer real implementations. Mock only at system boundaries (Firebase, network, clock).
- One logical assertion per test. Test names describe behavior. Arrange-Act-Assert.
- Widget tests (`testWidgets`) for UI behavior; plain `test()` for pure logic and
  policy classes (`ClientSearchPolicy`, etc.) — no Firebase needed.
- Always `await tester.pumpAndSettle()` after state changes. Assert `tester.takeException()` is null.

## Harness requirements

- Wrap widgets that use `ThemeNotifier.of(context)` in a full `ThemeNotifier(..., child: ...)`.
- Widgets that call `context.l10n` (including `StatusChip`) require
  `localizationsDelegates: [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate]`
  and `supportedLocales: AppLocalizations.supportedLocales` in their test `MaterialApp`.
- Widget tests that build a screen touching secure storage (anything reading the
  app-lock / onboarding flags or `AuthCache`) must call
  `FlutterSecureStorage.setMockInitialValues({})` in `setUp`. `SettingsScreen`
  additionally needs `PackageInfo.setMockInitialValues(...)` and a `ProviderScope`
  (it watches `appInfoProvider` + `appLockEnabledProvider` during build).
- **Any widget test reaching an account exit must override THREE providers:
  `appointmentImageLoaderProvider`, `clientsRepositoryProvider` and
  `appointmentsRepositoryProvider`.** `deregisterThisDevice` forgets everything
  the session cached locally, and each of the three fails a different way
  without an override. The image loader resolves the platform cache directory
  through `path_provider`, and a method channel never completes under
  `testWidgets`' fake clock, so the real one makes the test **HANG until its
  timeout rather than fail**, with no error naming the cause. The two
  repositories resolve `FirebaseFirestore.instance` when their providers are
  READ — which `DeviceDeregistrationDeps.from` now does — so they fail
  `[core/no-app]` on construction, before any teardown step runs. Override the
  loader with a subclass whose `clear()` is a no-op and the repositories with
  `implements X` + `noSuchMethod` stubs whose only real member is
  `clearCaches()` (see `_StubLoader`/`_StubClients`/`_StubAppointments` in
  `account_exit_listeners_test.dart`, the `_Recording*` trio in
  `device_deregistration_test.dart`, and `_exitOverrides` in
  `delete_account_flow_test.dart`). Same class of trap as the
  `FlutterSecureStorage.setMockInitialValues({})` rule above.
- **A bare `ProviderContainer` does NOT inherit `main()`'s retry override, and
  that matters for any test asserting an ERROR state.** `main.dart` passes
  `retry: (retryCount, error) => null` to its `ProviderScope`; without it,
  Riverpod 3's default exponential retry means an errored `FutureProvider`'s
  `.future` **never completes** and the test times out at 30 s rather than
  failing. Pass the same `retry:` to the container (see
  `widget_payload_provider_test.dart`,
  `active_user_identity_provider_test.dart`).
- **A platform gate is an injected predicate, not `dart:io Platform.isIOS`.**
  `flutter test` runs on the host, so a bare `Platform.isIOS` returns before
  any injectable point and leaves everything behind it unreachable — on the
  only platform that ships. `defaultIsIosPlatform` (`core/platform/`) is the
  default; `AppSyncListeners` and `LiveActivityRegistrationController` both take
  one. Add the seam rather than writing off the branch as device-only.
- Overflow regressions: sweep the screen at a small viewport (375×667) across
  text scales 0.8–2.0 and assert no exceptions — reuse the `_scaled` /
  `_pumpAtViewport` harness pattern in
  `test/features/auth/screens/auth_screens_scale_sweep_test.dart`.
- AutoDispose providers in tests need `container.listen(provider, (_, _) {})` in
  `setUp` so the family-keyed state survives across reads.
- Repositories that accept optional deps (e.g. `FirebaseEmployeesRepository`
  takes `auth`) must have those deps passed explicitly in tests — never let the
  constructor fall back to `FirebaseAuth.instance` or any singleton.
- Mocktail's `captureAny()` returns `Map<Object, Object?>`, not
  `Map<String, dynamic>`. Direct `as Map<String, dynamic>` cast throws at
  runtime. Use `(captured as Map).cast<String, dynamic>()` instead.
- `AppLogger` resolves `FirebaseCrashlytics` lazily, so controllers using
  `loggerProvider` in `catch` blocks don't need Firebase set up in tests.

## Device-only verification

- `ImagePickerService` has no unit tests — it is a thin wrapper over a
  method-channel plugin with no logic of its own. Verify picker fixes via
  `flutter run` on a device. **`ImageStorageService` is NOT in that category**
  (corrected 2026-08-15): it takes an injected `FirebaseStorage` and `AppLogger`,
  and its magic-byte rejection, 8 MB cap, `composeFileName` bound, legacy
  `_pathFromUrl` fallback and `object-not-found` swallow are all covered by
  `test/core/images/image_storage_service_test.dart`. Only the actual byte
  transfer (`putFile`) is device-only.
- The biometric app-lock (`AppLock`) and camera capture are device-only — not
  covered by the harness; verify via `flutter run` on a device.
- **Widget errors don't reach the console.** `main()` sets
  `FlutterError.onError = crashlytics.recordFlutterFatalError`, so build/layout/
  paint errors (overflows, null-checks) go silently to Crashlytics, *not*
  `flutter run` stdout. When chasing a silent UI failure, temporarily add
  `FlutterError.dumpErrorToConsole(details)` in that handler.
- **iOS device/simulator verification.** This app is iOS-only — `android/` was
  deleted 2026-08-05 and is gitignored precisely so `flutter` cannot regenerate
  it, so there is no `adb` workflow here and a bullet giving one pushes toward
  the tree resurrection the root `CLAUDE.md` exists to prevent. Screenshot a
  simulator with `xcrun simctl io booted screenshot out.png`; force the
  first-launch / onboarding path with `xcrun simctl uninstall booted
  <bundle-id>` followed by a fresh `flutter run`; check responsive breakpoints
  by booting a different device (`xcrun simctl list devices`, then
  `flutter run -d <udid>`) rather than by resizing, since iOS has no `wm size`
  equivalent. Reinstalling regenerates the App Attest/App Check debug token —
  re-register it in the Firebase Console (see the App Check note in
  `CLAUDE.md`).
