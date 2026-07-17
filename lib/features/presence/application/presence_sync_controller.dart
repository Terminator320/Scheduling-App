import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/permissions/location_permission_service.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart'
    show PushRegistrationController, shouldRegisterPush;
import 'package:scheduling/features/presence/data/presence_repository.dart';

final presenceRepositoryProvider = Provider<PresenceRepository>(
  (ref) => PresenceRepository(
    firestore: ref.watch(firestoreProvider),
    logger: ref.watch(loggerProvider),
  ),
);

final presenceSyncControllerProvider = Provider<PresenceSyncController>(
  PresenceSyncController.new,
);

/// Movement uploads at most this often — the stream's 250 m `distanceFilter`
/// handles granularity; this guards Firestore write volume on a highway.
const minPresenceUploadGap = Duration(minutes: 2);

/// Stationary re-upsert cadence. Keeps `updatedAt` fresh while tracking is
/// alive so the server can read staleness as "tracking is dead" (its window
/// is PRESENCE_STALE_MINUTES = 25 in functions/travel_utils.js — keep the two
/// in sync: window comfortably above two missed heartbeats).
const presenceHeartbeatEvery = Duration(minutes: 10);

/// Pure gate: signed-in active employees AND admins track presence (same
/// audience as [shouldRegisterPush]) — an admin assigned to a job gets the
/// timed "leave now" push, so their leave time deserves the same live-GPS
/// accuracy (decided 2026-07-13).
bool shouldTrackPresence({
  required String role,
  required String status,
  required bool signedIn,
}) => signedIn && status == 'active' && (role == 'employee' || role == 'admin');

/// Pure throttle for movement-driven fixes.
bool shouldWritePresenceFix({
  required DateTime? lastUploadAt,
  required DateTime now,
}) =>
    lastUploadAt == null ||
    now.difference(lastUploadAt) >= minPresenceUploadGap;

/// Pure gate for the heartbeat tick: only re-upsert when no movement fix has
/// gone out for a full heartbeat period (a fresh fix already reset the clock).
bool shouldHeartbeat({
  required DateTime? lastUploadAt,
  required DateTime now,
}) =>
    lastUploadAt != null &&
    now.difference(lastUploadAt) >= presenceHeartbeatEvery;

/// Delay until a throttled fix would be allowed to write, or null when a
/// write is already allowed now (mirrors [shouldWritePresenceFix]'s gate).
/// Used to arm a trailing-flush timer so the last fix in a burst of movement
/// still lands instead of being silently dropped by the throttle.
Duration? trailingFlushDelay({
  required DateTime? lastUploadAt,
  required DateTime now,
}) {
  if (shouldWritePresenceFix(lastUploadAt: lastUploadAt, now: now)) return null;
  return minPresenceUploadGap - now.difference(lastUploadAt!);
}

/// Owns the background position stream that keeps
/// `users/{docId}/presence/location` fresh for the travel-time reminders.
/// Driven by `main.dart` on every `currentUserDocProvider` emission (mirrors
/// [PushRegistrationController]); "backgrounded app" depth — tracking survives
/// backgrounding/screen-off but dies on force-quit until the next app open.
class PresenceSyncController {
  PresenceSyncController(this._ref, {FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final Ref _ref;
  final FirebaseAuth _auth;

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeat;
  Timer? _trailingFlush;
  AppLifecycleListener? _lifecycle;
  bool _busy = false;
  bool _pendingResync = false;
  String? _trackedUid;
  String? _docId;
  Position? _lastPosition;
  DateTime? _lastUploadAt;

  AppLogger get _logger => _ref.read(loggerProvider);

  /// Idempotent. A no-op for admins / signed-out users (and it tears the
  /// stream down when the gate stops passing). Safe to call on every
  /// account-doc emission and on app resume.
  Future<void> sync() async {
    // A concurrent call would otherwise be silently dropped; remember it and
    // re-run once in the finally so the latest account state always wins.
    if (_busy) {
      _pendingResync = true;
      return;
    }
    _busy = true;
    try {
      final signedIn = _auth.currentUser != null;
      final doc = _ref.read(currentUserDocProvider).value ?? const {};
      final role = (doc['role'] ?? '').toString().trim();
      final status = (doc['status'] ?? '').toString().trim();
      if (!shouldTrackPresence(
        role: role,
        status: status,
        signedIn: signedIn,
      )) {
        _stop();
        return;
      }
      // Resume restarts a stream killed by a mid-run permission flip and
      // pushes the retry right after the user returns from system Settings.
      _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(sync()));
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      // Fast path: already streaming for this uid.
      if (uid == _trackedUid && _positionSub != null) return;

      await _ref.read(firebaseReadyProvider.future).catchError((Object _) {});
      final permission = await _ref
          .read(locationPermissionServiceProvider)
          .ensureLocation();
      // Silent no-op on any non-grant — the OS prompt appears once on first
      // activation; never nag. The server's address-fallback chain covers an
      // untracked user.
      if (permission != LocationPermissionResult.granted) return;

      final match = await _ref
          .read(employeesRepositoryProvider)
          .findUserByUid(uid);
      final docId = match?.id;
      if (docId == null) {
        _logger.warn('PRESENCE no users doc for uid; skip tracking');
        return;
      }
      _start(docId: docId, uid: uid);
    } catch (e, st) {
      // sync() is called via `unawaited` — never let a failure escape as an
      // uncaught async error; report non-fatal instead.
      _logger.warn('PRESENCE sync failed', e, st);
    } finally {
      _busy = false;
      if (_pendingResync) {
        _pendingResync = false;
        unawaited(sync());
      }
    }
  }

  void _start({required String docId, required String uid}) {
    _stop();
    _trackedUid = uid;
    _docId = docId;
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: _settingsForPlatform(),
        ).listen(
          (position) {
            _lastPosition = position;
            final now = DateTime.now();
            if (shouldWritePresenceFix(lastUploadAt: _lastUploadAt, now: now)) {
              _lastUploadAt = now;
              _trailingFlush?.cancel();
              _trailingFlush = null;
              unawaited(_upload(position));
            } else {
              _armTrailingFlush(now);
            }
          },
          onError: (Object e, StackTrace st) {
            // A revoked permission / disabled service kills the stream. Stop
            // cleanly; the next sync() (app resume, account emission) re-runs
            // the whole gate and restarts when allowed again.
            _logger.warn('PRESENCE stream error', e, st);
            _stop();
          },
        );
    _heartbeat = Timer.periodic(presenceHeartbeatEvery, (_) {
      final position = _lastPosition;
      if (position == null) return;
      final now = DateTime.now();
      if (shouldHeartbeat(lastUploadAt: _lastUploadAt, now: now)) {
        _lastUploadAt = now;
        _trailingFlush?.cancel();
        _trailingFlush = null;
        unawaited(_upload(position));
      }
    });
  }

  /// Arms a one-shot timer so the last fix in a throttled burst still lands
  /// once the throttle window clears, instead of being silently dropped.
  void _armTrailingFlush(DateTime now) {
    final delay = trailingFlushDelay(lastUploadAt: _lastUploadAt, now: now);
    if (delay == null) return;
    _trailingFlush?.cancel();
    _trailingFlush = Timer(delay, () {
      _trailingFlush = null;
      final position = _lastPosition;
      final fireNow = DateTime.now();
      if (position == null ||
          !shouldWritePresenceFix(lastUploadAt: _lastUploadAt, now: fireNow)) {
        return;
      }
      _lastUploadAt = fireNow;
      unawaited(_upload(position));
    });
  }

  Future<void> _upload(Position position) {
    final docId = _docId;
    final uid = _trackedUid;
    if (docId == null || uid == null) return Future.value();
    return _ref
        .read(presenceRepositoryProvider)
        .upsertLocation(
          userDocId: docId,
          uid: uid,
          lat: position.latitude,
          lng: position.longitude,
        );
  }

  /// Device capability, not UI look — `defaultTargetPlatform`, not
  /// `context.isCupertino` (no BuildContext here; same rationale as
  /// `AddressMapLauncher`).
  LocationSettings _settingsForPlatform() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 250,
        activityType: ActivityType.automotiveNavigation,
        // The status-bar indicator while backgrounded is deliberate — honest
        // optics for staff whose location is being read.
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: true,
      );
    }
    return AndroidSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 250,
      // The foreground-service notification is what keeps the stream alive in
      // background on Android (dev harness only — never ships to Play, so the
      // untranslated text is acceptable).
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'ES Pro',
        notificationText:
            'Sharing your location for time-to-leave alerts and the staff map.',
      ),
    );
  }

  void _stop() {
    unawaited(_positionSub?.cancel());
    _positionSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _trailingFlush?.cancel();
    _trailingFlush = null;
    _trackedUid = null;
    _docId = null;
    _lastPosition = null;
    _lastUploadAt = null;
  }

  /// Best-effort teardown for sign-out / account deletion: stop the stream
  /// and delete the presence doc (privacy — no stale coordinates after
  /// leaving). Never throws — sign-out must not be blocked.
  Future<void> unregister() async {
    final docId = _docId;
    _stop();
    if (docId == null) return;
    try {
      await _ref
          .read(presenceRepositoryProvider)
          .deleteLocation(userDocId: docId);
    } catch (e, st) {
      _logger.warn('PRESENCE unregister failed', e, st);
    }
  }
}
