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

/// Whether this device can host a push-started Live Activity at all. Drives
/// whether the Settings row is shown — an Android or iOS 16 device gets no row
/// rather than a dead control. See
/// [LiveActivityRegistrationController.canHostCards].
final liveActivitySupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(liveActivityRegistrationControllerProvider).canHostCards(),
);

/// Pure gate: the Live Activity card is the lock-screen face of the travel-time
/// "leave now" push, so its audience is exactly the push audience. Delegates to
/// [shouldRegisterPush] so the two can't drift (the rule [PushRegistrationController]
/// and `shouldTrackPresence` already follow); iOS-version and user-setting
/// support is a separate, device-side gate inside the controller.
bool shouldRegisterLiveActivity({
  required String role,
  required String status,
  required bool signedIn,
}) => shouldRegisterPush(role: role, status: status, signedIn: signedIn);

/// Registers this device's Live Activity APNs tokens — the device-wide
/// **push-to-start** token plus one **update** token per live card — into
/// `users/{docId}/liveActivityTokens/{id}`, and tears them down on sign-out.
/// Driven by `main.dart` on every `currentUserDocProvider` emission and on
/// app-language change, mirroring [PushRegistrationController].
///
/// Deliberately NOT a copy of that controller's single `_registeredToken`
/// field: an FCM token is one-per-device, but an update token is one per
/// activity, so the live cards are tracked in a `Map<activityId, token>`.
///
/// Every path is iOS-gated and best-effort. A device below iOS 17.2, a user
/// who turned Live Activities off, or any failure here registers nothing and
/// behaves exactly as today — the `leaveNow` push fires independently and is
/// unchanged.
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

  // Resolved lazily, not in the constructor: this provider is read from the
  // appointment status path (`endLocalCards`), which runs in unit tests with
  // no Firebase app — a constructor-time `FirebaseAuth.instance` would throw
  // there even though every real path is iOS-gated.
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

  /// Idempotent. A no-op off iOS, for admins/employees who aren't active, and
  /// for devices that can't host a push-started card. Safe to call on every
  /// account-doc emission and on language change (re-upserts the locale). A
  /// concurrent call (e.g. a language change landing mid-sync) coalesces via
  /// [ReentrantSync] and re-runs once so the latest locale/doc always wins.
  Future<void> sync() async {
    if (!Platform.isIOS) return;
    await runCoalesced(_runSync);
  }

  Future<void> _runSync() async {
    try {
      await _syncGuarded();
    } catch (e, st) {
      // sync() is called via `unawaited` — never let a failure escape as an
      // uncaught async error (that would be recorded as a fatal crash).
      _logger.warn('LIVE-ACT sync failed', e, st);
    }
  }

  /// The body of [sync], run under the [ReentrantSync] guard.
  Future<void> _syncGuarded() async {
    // User opted out in Settings. The toggle itself calls [unregister] to end
    // the live card and drop the token rows; this only stops a later
    // account-doc emission from silently re-registering them. Awaiting `ready`
    // is required, not defensive: the provider returns its optimistic `true`
    // default until the stored value lands, so a cold-start sync would
    // otherwise re-register a device whose user had turned the card off.
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
    // Fast path: already subscribed for this uid+locale. Token rotations flow
    // through the live streams, so there's nothing to re-read or re-write.
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

  /// Whether this device can host a push-started card: iOS 17.2+
  /// (`allowsPushStart`), ActivityKit available, and Live Activities not
  /// switched off by the user in iOS Settings. Never throws — any plugin
  /// failure answers false, matching the feature's degrade-to-plain-push
  /// posture. Backs both the registration gate and the Settings row's
  /// visibility, so the two can't drift.
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

  /// Ends this device's live cards immediately. Called ONLY from [unregister]
  /// (the Settings opt-out), where clearing every card is exactly the intent.
  ///
  /// **Do NOT wire this to a status write.** `endAllActivities()` is
  /// device-wide, and this device cannot tell which appointment a
  /// push-started card belongs to — ActivityKit mints the id and the
  /// attributes aren't readable back. A tech marking the job they just left
  /// as done would therefore kill the card for the job they are currently
  /// driving to. Every terminal transition (done / cancelled / deleted /
  /// unassigned) is ended SERVER-side by `endCardOnTerminal`, which resolves
  /// the right card through the `liveActivityCards` marker.
  ///
  /// Best-effort: never throws.
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
      // Ends the cards and drops every per-activity row; only the device-wide
      // push-to-start row (which survives a completed job) is left to clear.
      await endLocalCards();
      // Resolved rather than read from `_docId`: a Settings opt-out can land
      // before the token stream has emitted, and a cold start with the
      // preference already off returns from _syncGuarded before `_docId` is
      // ever set — in both cases the row exists on the server and must go.
      final docId = _docId ?? await _resolveUserDocId();
      if (docId != null) {
        // By kind, not by id: the push-to-start doc id IS the token, which
        // this session may never have seen.
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
