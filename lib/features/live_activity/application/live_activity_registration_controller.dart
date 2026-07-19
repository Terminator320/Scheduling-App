import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/activity_update.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart'
    show widgetAppGroupId;
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
class LiveActivityRegistrationController {
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
  bool _busy = false;
  bool _pendingResync = false;
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
  /// account-doc emission and on language change (re-upserts the locale).
  Future<void> sync() async {
    if (!Platform.isIOS) return;
    // A concurrent call (e.g. a language change landing mid-sync) would
    // otherwise be silently dropped — remember it and re-run once in the
    // finally so the latest locale/doc always wins.
    if (_busy) {
      _pendingResync = true;
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

    _busy = true;
    try {
      await _ref.read(firebaseReadyProvider.future).catchError((Object _) {});
      if (uid == null) return;
      if (!await _ensurePlugin()) return;

      final match = await _ref
          .read(employeesRepositoryProvider)
          .findUserByUid(uid);
      final docId = match?.id;
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
    } catch (e, st) {
      // sync() is called via `unawaited` — never let a failure escape as an
      // uncaught async error (that would be recorded as a fatal crash).
      _logger.warn('LIVE-ACT sync failed', e, st);
    } finally {
      _busy = false;
      if (_pendingResync) {
        _pendingResync = false;
        unawaited(sync());
      }
    }
  }

  /// Initializes the plugin once and answers whether this device can host a
  /// push-started card: iOS 17.2+ (`pushToStartTokenUpdates`), Live Activities
  /// supported, and not switched off by the user in Settings.
  Future<bool> _ensurePlugin() async {
    if (!await _plugin.areActivitiesSupported()) return false;
    if (!await _plugin.areActivitiesEnabled()) return false;
    if (!await _plugin.allowsPushStart()) return false;
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

  /// Ends this device's live cards immediately — called when the user marks a
  /// job done or cancels it in-app, so the Lock Screen clears without waiting
  /// for the server's end push. At most one card is live at a time by design
  /// (one "leave now" per tech), so ending all of them is the whole set.
  /// Best-effort: never throws, and the server's end push remains the backstop.
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
    final docId = _docId;
    final activityIds = _activityTokens.keys.toList();
    final pushToStart = _pushToStartToken;
    try {
      if (_pluginReady) await _plugin.endAllActivities();
      if (docId != null) {
        final repository = _ref.read(liveActivityTokenRepositoryProvider);
        for (final activityId in activityIds) {
          await repository.deleteToken(userDocId: docId, docId: activityId);
        }
        if (pushToStart != null) {
          await repository.deleteToken(userDocId: docId, docId: pushToStart);
        }
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

  Future<void> _cancelStreams() async {
    await _pushToStartSub?.cancel();
    _pushToStartSub = null;
    await _activitySub?.cancel();
    _activitySub = null;
  }
}
