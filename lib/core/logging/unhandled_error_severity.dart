import 'package:firebase_core/firebase_core.dart';

/// Whether an error that reached a global handler should be filed as a fatal.
///
/// A Firestore `permission-denied` that arrives unhandled is not a crash. It is
/// the signature of auth teardown racing a live listener: revoking the token
/// (sign-out, account deletion, the signup-code rollback) denies any snapshot
/// stream still attached, and when the owning provider is disposed in the same
/// instant the error has no consumer left and falls through to the zone. The
/// app keeps running, so reporting it as a crash overstates it.
///
/// It stays recorded as a non-fatal — the stream that owns the query logs its
/// own tagged `warn` too, so a genuine rules rejection still surfaces twice.
bool isFatalUnhandledError(Object error) {
  return !(error is FirebaseException && error.code == 'permission-denied');
}
