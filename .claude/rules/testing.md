---
paths:
  - "test/**"
  - "functions/test/**"
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

- `ImagePickerService` / `ImageStorageService` have no unit tests — they depend
  on method-channel plugins. Verify image-related fixes via `flutter run` on a device.
- The biometric app-lock (`AppLock`) and camera capture are device-only — not
  covered by the harness; verify via `flutter run` on a device.
- **Widget errors don't reach the console.** `main()` sets
  `FlutterError.onError = crashlytics.recordFlutterFatalError`, so build/layout/
  paint errors (overflows, null-checks) go silently to Crashlytics, *not*
  `flutter run` stdout. When chasing a silent UI failure, temporarily add
  `FlutterError.dumpErrorToConsole(details)` in that handler.
- **Android device verification (package `net.vogas.scheduling`):** screenshot
  with `adb -s <id> exec-out screencap -p > out.png`; force the first-launch /
  onboarding path with `adb -s <id> shell pm clear net.vogas.scheduling`; exercise
  responsive breakpoints with `adb -s <id> shell wm size 1600x900` then
  `wm size reset`. Clearing app data regenerates the App Check debug token —
  re-register it in the Firebase Console (see the App Check note in CLAUDE.md).
