import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// App Group shared with the iOS WidgetKit extension.
const _appGroupId = 'group.net.vogas.scheduling';
const _iosWidgetName = 'ScheduleWidget';
const _payloadKey = 'schedulePayload';

Map<String, dynamic> _job(AppointmentRecord a) => {
  // Carried so a widget tap can deep-link straight to this appointment's
  // detail sheet (the Swift widget builds `esproschedule://appointment?id=…`).
  'id': a.id,
  // Emit an absolute UTC instant (…Z). startTime is a *local* DateTime
  // (Firestore Timestamp.toDate()), so a bare toIso8601String() has no zone
  // designator — which the widget's ISO8601DateFormatter cannot parse. The
  // Swift side renders it back in the device's local time zone.
  'startTime': a.startTime.toUtc().toIso8601String(),
  'clientName': a.clientName,
  'title': a.title,
  'address': a.address,
  'status': a.status,
};

/// Serializes an employee's remaining-today jobs and next upcoming job into
/// the JSON the iOS widget renders. Pure — unit-testable. `nextJob` may be a
/// job on a later day (so the small widget still shows something after today's
/// jobs are done); `jobs` is only today's remaining, non-terminal visits.
Map<String, dynamic> buildWidgetPayload(
  List<AppointmentRecord> appointments,
  DateTime now, {
  String locale = 'en',
}) {
  final dayEnd = DateTime(now.year, now.month, now.day + 1);
  final upcoming =
      appointments
          .where(
            (a) =>
                !AppointmentStatus.fromRaw(a.status).isTerminal &&
                a.startTime.isAfter(now),
          )
          .toList()
        ..sort((x, y) => x.startTime.compareTo(y.startTime));
  final todayRemaining = upcoming
      .where((a) => a.startTime.isBefore(dayEnd))
      .toList();
  return {
    'locale': locale,
    'generatedAt': now.toIso8601String(),
    'todayCount': todayRemaining.length,
    'jobs': [for (final a in todayRemaining) _job(a)],
    'nextJob': upcoming.isEmpty ? null : _job(upcoming.first),
  };
}

/// Writes the widget payload into the App Group and refreshes the widget.
/// iOS-only (no-op elsewhere); device-verified (platform-channel plugin, no
/// unit tests — the payload builder above is the tested part).
class WidgetSyncService {
  WidgetSyncService({AppLogger? logger}) : _logger = logger ?? AppLogger();

  final AppLogger _logger;

  /// Signature of the last successful write: `null` = nothing written yet,
  /// [_clearedState] = the widget was cleared, otherwise the encoded
  /// job-relevant payload. Lets `sync`/`clear` skip the App Group write +
  /// WidgetKit reload when the visible jobs are unchanged — the appointments
  /// stream re-emits far more often than the schedule actually changes.
  static const _clearedState = '__cleared__';
  String? _lastState;

  Future<void> sync(Map<String, dynamic> payload) async {
    if (!Platform.isIOS) return;
    final signature = _signatureOf(payload);
    if (signature == _lastState) return;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
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
      await HomeWidget.setAppGroupId(_appGroupId);
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

/// The signed-in active employee's users doc id (the key
/// `appointments.employeeIds` holds), or null for admins / signed-out.
final widgetEmployeeIdProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final doc = ref.watch(currentUserDocProvider).value ?? const {};
  final role = (doc['role'] ?? '').toString().trim();
  final status = (doc['status'] ?? '').toString().trim();
  if (role != 'employee' || status != 'active') return null;
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return null;
  final match = await ref.watch(employeesRepositoryProvider).findUserByUid(uid);
  return match?.id;
});

/// The current widget payload for the signed-in employee, or `data(null)` when
/// the widget should be cleared (admin / signed-out). Watches a today+lookahead
/// range so "next job" survives an empty today.
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
      final now = DateTime.now();
      final range = AppointmentDateRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day + 3),
      );
      final appts = ref.watch(
        myAppointmentsProvider((employeeId: empId, range: range)),
      );
      final locale = AppLanguageController.instance.value == 'fr' ? 'fr' : 'en';
      return appts.whenData(
        (list) => buildWidgetPayload(list, DateTime.now(), locale: locale),
      );
    });
