import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// App Group shared with the iOS WidgetKit extension. This is public because
/// the app has to call `HomeWidget.setAppGroupId` with it before any widget
/// read, or iOS throws `AppGroupId not set`.
const widgetAppGroupId = 'group.net.vogas.scheduling';
const _iosWidgetName = 'ScheduleWidget';
const _payloadKey = 'schedulePayload';

Map<String, dynamic> _job(AppointmentRecord a) => {
  // Carried so tapping the widget can deep-link back to the job. `?? ''`
  // avoids sending null, since Swift decodes this field as non-optional.
  'id': a.id ?? '',
  // Emit an absolute UTC instant with the Z suffix — a bare toIso8601String()
  // omits the zone designator the widget's formatter needs.
  'startTime': a.startTime.toUtc().toIso8601String(),
  'clientName': a.clientName,
  'title': a.title,
  'address': a.address,
  'status': a.status,
  // The widget speaks "All day" instead of the stored midnight–23:59 pair.
  'isAllDay': a.isAllDay,
};

/// How long after the last job of the day is finished the widget keeps showing
/// today before it rolls forward to tomorrow's schedule.
const widgetRolloverGrace = Duration(hours: 1);

/// Serializes an employee's schedule into the JSON the iOS widget renders.
/// Pure and unit-testable — carries today's and tomorrow's jobs plus a
/// `rolloverAt` instant so WidgetKit can switch on-device without the app running.
Map<String, dynamic> buildWidgetPayload(
  List<AppointmentRecord> appointments,
  DateTime now, {
  String locale = 'en',
}) {
  final startOfToday = now.dateOnly;
  final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);
  final startOfDayAfter = DateTime(now.year, now.month, now.day + 2);

  bool inRange(AppointmentRecord a, DateTime lo, DateTime hi) =>
      !a.startTime.isBefore(lo) && a.startTime.isBefore(hi);
  AppointmentStatus statusOf(AppointmentRecord a) =>
      AppointmentStatus.fromRaw(a.status);

  final todayAll = appointments
      .where((a) => inRange(a, startOfToday, startOfTomorrow))
      .toList();
  final todayIncomplete = todayAll
      .where((a) => !statusOf(a).isTerminal)
      .toList();
  // "Still ahead of you today". An all-day block starts at midnight, so a
  // start-time test would drop it from today the moment the day began — it
  // stays listed until its 23:59 end passes.
  bool stillAhead(AppointmentRecord a) =>
      a.isAllDay ? a.endTime.isAfter(now) : a.startTime.isAfter(now);

  final todayJobs = todayIncomplete.where(stillAhead).toList()
    ..sort((x, y) => x.startTime.compareTo(y.startTime));
  final tomorrowJobs =
      appointments
          .where(
            (a) =>
                inRange(a, startOfTomorrow, startOfDayAfter) &&
                !statusOf(a).isTerminal,
          )
          .toList()
        ..sort((x, y) => x.startTime.compareTo(y.startTime));

  DateTime? rolloverAt;
  if (todayIncomplete.isEmpty) {
    final finished = todayAll.where((a) => !statusOf(a).isCancelled).toList();
    // If today's jobs are empty or all cancelled, use a stable past instant so
    // we don't churn; otherwise roll over 1h after the last job ends.
    rolloverAt = finished.isEmpty
        ? startOfToday
        : finished
              .map((a) => a.endTime)
              .reduce((a, b) => a.isAfter(b) ? a : b)
              .add(widgetRolloverGrace);
  }

  String iso(DateTime d) => d.toUtc().toIso8601String();
  return {
    'locale': locale,
    'generatedAt': iso(now),
    'todayDate': iso(startOfToday),
    'tomorrowDate': iso(startOfTomorrow),
    'rolloverAt': rolloverAt == null ? null : iso(rolloverAt),
    'todayJobs': [for (final a in todayJobs) _job(a)],
    'tomorrowJobs': [for (final a in tomorrowJobs) _job(a)],
  };
}

/// Writes an already-encoded payload JSON into the App Group and reloads the
/// widget. iOS-only — used by the FCM background handler, which has no
/// Riverpod container to build the payload the normal way.
Future<void> writeWidgetPayloadJson(String payloadJson) async {
  if (!Platform.isIOS) return;
  if (payloadJson.isEmpty) return;
  try {
    await HomeWidget.setAppGroupId(widgetAppGroupId);
    await HomeWidget.saveWidgetData<String>(_payloadKey, payloadJson);
    await HomeWidget.updateWidget(iOSName: _iosWidgetName);
  } catch (_) {
    // Best-effort: a background write failure just leaves the widget showing
    // its last state until the app next runs and syncs.
  }
}

/// Writes the widget payload into the App Group and refreshes the widget.
/// iOS-only, and verified on-device rather than with unit tests — the payload
/// builder above is the part that's actually tested.
class WidgetSyncService {
  WidgetSyncService({AppLogger? logger}) : _logger = logger ?? AppLogger();

  final AppLogger _logger;

  /// Signature of the last successful write, used to dedup repeat syncs.
  /// Null means nothing's been written yet; [_clearedState] means we cleared it.
  static const _clearedState = '__cleared__';
  String? _lastState;

  Future<void> sync(Map<String, dynamic> payload) async {
    if (!Platform.isIOS) return;
    final signature = _signatureOf(payload);
    if (signature == _lastState) return;
    try {
      await HomeWidget.setAppGroupId(widgetAppGroupId);
      await HomeWidget.saveWidgetData<String>(_payloadKey, jsonEncode(payload));
      await HomeWidget.updateWidget(iOSName: _iosWidgetName);
      _lastState = signature;
    } catch (e, st) {
      _logger.warn('WIDGET sync failed', e, st);
    }
  }

  Future<void> clear() async {
    if (!Platform.isIOS) return;
    if (_lastState == _clearedState) return;
    try {
      await HomeWidget.setAppGroupId(widgetAppGroupId);
      await HomeWidget.saveWidgetData<String>(_payloadKey, null);
      await HomeWidget.updateWidget(iOSName: _iosWidgetName);
      _lastState = _clearedState;
    } catch (e, st) {
      _logger.warn('WIDGET clear failed', e, st);
    }
  }

  /// The job-relevant slice of [payload] — everything except the ever-changing
  /// `generatedAt` stamp, which must not defeat the unchanged-jobs check.
  static String _signatureOf(Map<String, dynamic> payload) {
    final meaningful = Map<String, dynamic>.of(payload)..remove('generatedAt');
    return jsonEncode(meaningful);
  }

  /// Test hook for the `generatedAt`-insensitive dedup signature.
  @visibleForTesting
  static String signatureForTesting(Map<String, dynamic> payload) =>
      _signatureOf(payload);
}

final widgetSyncServiceProvider = Provider<WidgetSyncService>(
  (ref) => WidgetSyncService(logger: ref.watch(loggerProvider)),
);

/// The signed-in user's doc id, or null when signed out. Both employees and
/// admins qualify here, since admins can assign themselves to jobs too.
final widgetEmployeeIdProvider = FutureProvider.autoDispose<String?>(
  (ref) async => (await ref.watch(activeUserIdentityProvider.future))?.docId,
);

/// The current widget payload for the signed-in employee, or null when the
/// widget should be cleared. Watches today plus the lookahead range.
final widgetPayloadProvider =
    Provider.autoDispose<AsyncValue<Map<String, dynamic>?>>((ref) {
      final empIdAsync = ref.watch(widgetEmployeeIdProvider);
      if (empIdAsync.isLoading) return const AsyncValue.loading();
      final empId = empIdAsync.value;
      if (empId == null) {
        return const AsyncValue<Map<String, dynamic>?>.data(
          null,
        );
      }
      // Rebuild on day rollover so app doesn't keep showing yesterday's jobs.
      final today = ref.watch(currentDayProvider);
      final range = AppointmentDateRange(
        start: today,
        end: DateTime(today.year, today.month, today.day + 3),
      );
      final appts = ref.watch(
        myAppointmentsProvider((employeeId: empId, range: range)),
      );
      final locale = AppLanguageController.instance.value == 'fr' ? 'fr' : 'en';
      return appts.whenData(
        (list) => buildWidgetPayload(list, DateTime.now(), locale: locale),
      );
    });
