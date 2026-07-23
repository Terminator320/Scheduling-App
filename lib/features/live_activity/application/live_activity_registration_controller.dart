import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/activity_update.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/core/utils/reentrant_sync.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart'
    show widgetAppGroupId;
import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:scheduling/features/live_activity/data/live_activity_token_repository.dart';
import 'package:scheduling/features/live_activity/domain/live_activity_token.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart'
    show PushRegistrationController, shouldRegisterPush;

final liveActivityTokenRepositoryProvider =
    Provider<LiveActivityTokenRepository>(
      (ref) => LiveActivityTokenRepository(
        firestore: ref.watch(firestoreProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

final liveActivityRegistrationControllerProvider =
    Provider<LiveActivityRegistrationController>(
      LiveActivityRegistrationController.new,
    );

/// Whether this device can host a push-started Live Activity; drives Settings row visibility.
final liveActivitySupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(liveActivityRegistrationControllerProvider).canHostCards(),
);

/// Gate for Live Activity registration; delegates to [shouldRegisterPush] so the two can't drift.
bool shouldRegisterLiveActivity({
  required String role,
  required String status,
  required bool signedIn,
}) => shouldRegisterPush(role: role, status: status, signedIn: signedIn);

/// Registers device's Live Activity APNs tokens (device-wide push-to-start and per-activity update tokens) into `users/{docId}/liveActivityTokens/{id}`.
/// iOS-gated and best-effort; all failures degrade to plain `leaveNow` push unchanged.
class LiveActivityRegistrationController with ReentrantSync {
  LiveActivityRegistrationController(
    this._ref, {
    FirebaseAuth? auth,
    LiveActivities? plugin,
  }) : _injectedAuth = auth,
       _injectedPlugin = plugin;

  final Ref _ref;
  final FirebaseAuth? _injectedAuth;
  final LiveActivities? _injectedPlugin;

  // Resolved lazily (not in constructor) since endLocalCards runs in unit tests without Firebase.
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;
  LiveActivities get _plugin =>
      _injectedPlugin ?? (_lazyPlugin ??= LiveActivities());
  LiveActivities? _lazyPlugin;

  StreamSubscription<String>? _pushToStartSub;
  StreamSubscription<ActivityUpdate>? _activitySub;
  bool _pluginReady = false;
  String? _docId;
  String? _uid;
  String? _locale;
  String? _pushToStartToken;

  /// Live cards keyed by activity id — one update token each.
  final Map<String, String> _activityTokens = <String, String>{};

  AppLogger get _logger => _ref.read(loggerProvider);

  static String _currentLocale() =>
      AppLanguageController.instance.value == 'fr' ? 'fr' : 'en';

  /// Idempotent and safe to call on every account-doc emission or language change; concurrent calls coalesce so latest state wins.
  Future<void> sync() async {
    if (!Platform.isIOS) return;
    await runCoalesced(_runSync);
  }

  Future<void> _runSync() async {
    try {
      await _syncGuarded();
    } catch (e, st) {
      // sync() is unawaited; don't let failures escape as uncaught async errors.
      _logger.warn('LIVE-ACT sync failed', e, st);
    }
  }

  /// The body of [sync], run under the [ReentrantSync] guard.
  Future<void> _syncGuarded() async {
    // Await ready before reading preference (cold-start defaults to true, would re-register opted-out device).
    await _ref.read(liveActivityEnabledProvider.notifier).ready;
    if (!_ref.read(liveActivityEnabledProvider)) {
      await _cancelStreams();
      return;
    }
    final signedIn = _auth.currentUser != null;
    final doc = _ref.read(currentUserDocProvider).value ?? const {};
    final role = (doc['role'] ?? '').toString().trim();
    final status = (doc['status'] ?? '').toString().trim();
    if (!shouldRegisterLiveActivity(
      role: role,
      status: status,
      signedIn: signedIn,
    )) {
      await _cancelStreams();
      return;
    }

    final uid = _auth.currentUser?.uid;
    final locale = _currentLocale();
    // Fast path: already subscribed for this uid+locale; token rotations flow through streams.
    if (uid != null &&
        uid == _uid &&
        locale == _locale &&
        _pushToStartSub != null) {
      return;
    }

    await _ref.read(firebaseReadyProvider.future).catchError((Object _) {});
    if (uid == null) return;
    if (!await _ensurePlugin()) return;

    final docId = await _resolveUserDocId();
    if (docId == null) {
      _logger.warn('LIVE-ACT no users doc for uid; skip token upsert');
      return;
    }

    _docId = docId;
    _uid = uid;
    _locale = locale;
    await _reupsertKnownTokens();
    _subscribePushToStart();
    _subscribeActivityUpdates();
  }

  /// Whether this device can host a push-started card (iOS 17.2+, ActivityKit available, user-enabled); never throws.
  Future<bool> canHostCards() async {
    if (!Platform.isIOS) return false;
    try {
      return await _plugin.areActivitiesSupported() &&
          await _plugin.areActivitiesEnabled() &&
          await _plugin.allowsPushStart();
    } catch (e, st) {
      _logger.warn('LIVE-ACT support probe failed', e, st);
      return false;
    }
  }

  /// [canHostCards], plus a one-time plugin init for the device that can.
  Future<bool> _ensurePlugin() async {
    if (!await canHostCards()) return false;
    if (!_pluginReady) {
      await _plugin.init(appGroupId: widgetAppGroupId);
      _pluginReady = true;
    }
    return true;
  }

  /// Language change / account switch: re-stamp the rows this device already
  /// owns so their `locale` (which drives the card's EN/FR text) follows the
  /// app, instead of waiting for iOS to rotate a token.
  Future<void> _reupsertKnownTokens() async {
    final pushToStart = _pushToStartToken;
    if (pushToStart != null) {
      await _upsert(
        token: pushToStart,
        kind: LiveActivityTokenKind.pushToStart,
      );
    }
    for (final entry in _activityTokens.entries) {
      await _upsert(
        token: entry.value,
        kind: LiveActivityTokenKind.update,
        activityId: entry.key,
      );
    }
  }

  void _subscribePushToStart() {
    unawaited(_pushToStartSub?.cancel());
    _pushToStartSub = _plugin.pushToStartTokenUpdateStream.listen(
      (token) {
        _pushToStartToken = token;
        unawaited(
          _upsert(token: token, kind: LiveActivityTokenKind.pushToStart),
        );
      },
      onError: (Object e, StackTrace st) =>
          _logger.warn('LIVE-ACT push-to-start stream error', e, st),
    );
  }

  void _subscribeActivityUpdates() {
    unawaited(_activitySub?.cancel());
    _activitySub = _plugin.activityUpdateStream.listen(
      (event) {
        event.mapOrNull<void>(
          active: (value) {
            _activityTokens[value.activityId] = value.activityToken;
            unawaited(
              _upsert(
                token: value.activityToken,
                kind: LiveActivityTokenKind.update,
                activityId: value.activityId,
              ),
            );
          },
          // `ended` also covers a dismissed card: its update token is dead, so
          // drop the row rather than leaving the server pushing into a void.
          ended: (value) => unawaited(_forgetActivity(value.activityId)),
        );
      },
      onError: (Object e, StackTrace st) =>
          _logger.warn('LIVE-ACT activity stream error', e, st),
    );
  }

  Future<void> _upsert({
    required String token,
    required LiveActivityTokenKind kind,
    String? activityId,
  }) async {
    final docId = _docId;
    final uid = _uid;
    if (docId == null || uid == null) return;
    await _ref
        .read(liveActivityTokenRepositoryProvider)
        .upsertToken(
          userDocId: docId,
          docId: liveActivityTokenDocId(
            kind: kind,
            token: token,
            activityId: activityId,
          ),
          token: token,
          kind: kind,
          locale: _locale ?? _currentLocale(),
          uid: uid,
          expiresAt: liveActivityTokenExpiry(kind: kind, now: DateTime.now()),
        );
  }

  Future<void> _forgetActivity(String activityId) async {
    _activityTokens.remove(activityId);
    final docId = _docId;
    if (docId == null) return;
    await _ref
        .read(liveActivityTokenRepositoryProvider)
        .deleteToken(userDocId: docId, docId: activityId);
  }

  /// Ends this device's live cards immediately (Settings opt-out only).
  /// Do NOT wire to status write: endAllActivities() is device-wide and can't resolve per-appointment cards (ActivityKit id is not readable back).
  /// Terminal transitions are ended server-side by endCardOnTerminal via the liveActivityCards marker.
  Future<void> endLocalCards() async {
    if (!Platform.isIOS || !_pluginReady) return;
    try {
      await _plugin.endAllActivities();
    } catch (e, st) {
      _logger.warn('LIVE-ACT endLocalCards failed', e, st);
    }
    // The `ended` stream events clear these rows too; sweeping here means a
    // missed event can't leave the server pushing at a card that's gone.
    for (final activityId in _activityTokens.keys.toList()) {
      await _forgetActivity(activityId);
    }
  }

  /// Best-effort de-registration for sign-out / account deletion: end any live
  /// card (no client's name left on a signed-out Lock Screen) and delete this
  /// device's token rows. Never throws — sign-out must not be blocked.
  Future<void> unregister() async {
    try {
      // Ends the cards and drops every per-activity row (push-to-start row left for clear).
      await endLocalCards();
      // Resolve docId in case _docId was never set (opt-out before token stream emitted, or cold-start with preference off).
      final docId = _docId ?? await _resolveUserDocId();
      if (docId != null) {
        // By kind, not by id: push-to-start doc id IS the token (session may never have seen).
        await _ref
            .read(liveActivityTokenRepositoryProvider)
            .deleteTokensOfKind(
              userDocId: docId,
              kind: LiveActivityTokenKind.pushToStart,
            );
      }
    } catch (e, st) {
      _logger.warn('LIVE-ACT unregister failed', e, st);
    } finally {
      await _cancelStreams();
      _docId = null;
      _uid = null;
      _locale = null;
      _pushToStartToken = null;
      _activityTokens.clear();
    }
  }

  /// The users-doc id for the signed-in uid, or null when signed out or the
  /// lookup fails. Never throws — [unregister] must not block sign-out.
  Future<String?> _resolveUserDocId() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    try {
      final match = await _ref
          .read(employeesRepositoryProvider)
          .findUserByUid(uid);
      return match?.id;
    } catch (e, st) {
      _logger.warn('LIVE-ACT resolve users doc failed', e, st);
      return null;
    }
  }

  Future<void> _cancelStreams() async {
    await _pushToStartSub?.cancel();
    _pushToStartSub = null;
    await _activitySub?.cancel();
    _activitySub = null;
  }
}
