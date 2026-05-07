# Changelog

All notable changes to this project are documented here.


- **MAJOR** (`x.0.0`) — incompatible / breaking changes.
- **MINOR** (`1.x.0`) — new functionality, backward-compatible.
- **PATCH** (`1.0.x`) — backward-compatible bug fixes only.

The `+N` build number after the version (e.g. `1.1.0+5`) is the store version
code; it increments by one on every store upload regardless of the semver part.

## [1.1.1+6] - 2026-06-02

### Fixed
- Login no longer fails with a false "this account has been disabled" crash or a
  generic "something went wrong please try again" banner. The deleted-account
  watcher mistook the transient empty placeholder doc — surfaced while the
  `authStateChanges()` uid stream lags `FirebaseAuth.currentUser` right after
  sign-in — for a real deletion. It now fires only for a settled, non-loading
  empty doc with a resolved uid (`isAccountDeletionSignal`).
- The account-exit handler can no longer wedge the root navigator. It previously
  pushed a route while the navigator was mid-transition, throwing `!_debugLocked`
  and permanently locking navigation — which cascaded into the login "something
  went wrong" banner and dead Create-account / Forgot-password links. Navigation
  is now deferred to a post-frame callback (idle navigator) and guarded against
  re-entrancy across the three account listeners.
- Login failures are now logged (`login.sign_in`) instead of being silently
  swallowed, so post-authentication errors surface in the debug console.

## [1.1.0+5] - 2026-06-02

### Added
- First-launch onboarding carousel, shown once and gated by an encrypted
  `onboardingSeen` flag (`smooth_page_indicator`).
- Biometric app-lock that gates the whole app on cold start and resume
  (`local_auth`), toggled from Settings and stored as an encrypted flag.
- Appointment image carousel and in-app camera capture, with runtime camera
  permission handling (`permission_handler`).
- Paginated clients list with infinite scroll (`infinite_scroll_pagination`).
- Encrypted at-rest secure storage for cached identity and remembered login
  email (`flutter_secure_storage`).
- App version display in Settings.

### Changed
- Performance and security hardening pass across the codebase (durable
  Firestore-backed rate limiting on auth callables, callable payload
  sanitization, and related cleanup).
- Code-structure simplification and documentation of plugin features in
  `docs/ARCHITECTURE.md`.

### Fixed
- Appointment card no longer crashes when viewing events on other days. The
  card's `IntrinsicHeight` (which stretches the employee-color bar) could not
  compute intrinsic dimensions through `AutoSizeText`'s internal `LayoutBuilder`,
  which surfaced in release builds as a paint-time `Null check operator used on
  a null value`. The title is now a plain `Text`.

## [1.0.3+4] - 2026-05-23

### Fixed
- Account deletion reliability and an accompanying Firestore security-rules
  update.

## [1.0.2+3] - 2026-05-21

### Added
- Adaptive / responsive layout, native splash screen, and app launcher icons.
- Full English/French localization via `gen_l10n` with `@key` metadata.

### Changed
- Hardcoded values refactored into design tokens and localized strings.

### Fixed
- Sign-up errors no longer collapse into a generic message in release builds.

## [1.0.0+1] - 2026-03-26

### Added
- Initial release: appointment scheduling, client records, employee management,
  and photo documentation, backed by Firebase (Auth, Firestore, Storage,
  App Check).
