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
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// App Group shared with the iOS WidgetKit extension. This is public because
/// the app has to call `HomeWidget.setAppGroupId` with it before any widget
/// read, or iOS throws `AppGroupId not set`.
const widgetAppGroupId = 'group.net.vogas.scheduling';
const _iosWidgetName = 'ScheduleWidget';
const _payloadKey = 'schedulePayload';

/// One job as the widget renders it, scoped to the day it appears on.
///
/// [slice] carries that day's window and position in the run — the widget must
/// show TODAY's clock, not the run's first morning. `dayIndex`/`dayCount` are
/// omitted for a single-day job so a pre-multi-day Swift decoder still parses
/// (it reads them as `Int?`) and so the widget shows no counter.
Map<String, dynamic> _job(AppointmentDaySlice slice) {
  final a = slice.appointment;
  return {
    // Carried so tapping the widget can deep-link back to the job. `?? ''`
    // avoids sending null, since Swift decodes this field as non-optional.
    'id': a.id ?? '',
    // Emit an absolute UTC instant with the Z suffix — a bare toIso8601String()
    // omits the zone designator the widget's formatter needs.
    'startTime': slice.windowStart.toUtc().toIso8601String(),
    'clientName': a.clientName,
    'title': a.title,
    'address': a.address,
    'status': a.status,
    // The widget speaks "All day" instead of the stored midnight–23:59 pair.
    'isAllDay': a.isAllDay,
    if (slice.isMultiDay) 'dayIndex': slice.dayIndex,
    if (slice.isMultiDay) 'dayCount': slice.dayCount,
  };
}

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

  AppointmentStatus statusOf(AppointmentRecord a) =>
      AppointmentStatus.fromRaw(a.status);

  // A job is "on" a day when it WORKS that day — not when its stored startTime
  // happens to fall in it. Without this a run that began yesterday is invisible
  // today, which is the whole point of multi-day support.
  List<AppointmentDaySlice> slicesOn(DateTime day) => [
    for (final a in appointments) ?sliceFor(a, day),
  ];

  final todayAll = slicesOn(startOfToday);
  final todayIncomplete = todayAll
      .where((s) => !statusOf(s.appointment).isTerminal)
      .toList();
  // "Still ahead of you today", judged against THIS day's window. An all-day
  // block starts at midnight, so a start test would drop it the moment the day
  // began — it stays listed until its 23:59 end passes.
  bool stillAhead(AppointmentDaySlice s) => s.appointment.isAllDay
      ? s.windowEnd.isAfter(now)
      : s.windowStart.isAfter(now);

  final todayJobs = todayIncomplete.where(stillAhead).toList()
    ..sort((x, y) => x.windowStart.compareTo(y.windowStart));
  final tomorrowJobs =
      slicesOn(
          startOfTomorrow,
        ).where((s) => !statusOf(s.appointment).isTerminal).toList()
        ..sort((x, y) => x.windowStart.compareTo(y.windowStart));

  DateTime? rolloverAt;
  if (todayIncomplete.isEmpty) {
    final finished = todayAll
        .where((s) => !statusOf(s.appointment).isCancelled)
        .toList();
    // If today's jobs are empty or all cancelled, use a stable past instant so
    // we don't churn; otherwise roll over 1h after the last job ends. The
    // window end, not the record's — a run rolls the widget over at the end of
    // TODAY's window, not at the end of the whole run.
    rolloverAt = finished.isEmpty
        ? startOfToday
        : finished
              .map((s) => s.windowEnd)
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
      // The shared mirror window, not this payload's own today+tomorrow: the
      // Siri snapshot holds a permanent listener on the same family, and its
      // window is a strict superset of what the widget needs. Asking for the
      // same range value means one listener for both.
      // `buildWidgetPayload` re-scopes to today/tomorrow in Dart regardless.
      final range = AppointmentDateRange.forMirrors(today);
      final appts = ref.watch(
        myAppointmentsProvider((employeeId: empId, range: range)),
      );
      final locale = AppLanguageController.instance.value == 'fr' ? 'fr' : 'en';
      return appts.whenData(
        (list) => buildWidgetPayload(list, DateTime.now(), locale: locale),
      );
    });
