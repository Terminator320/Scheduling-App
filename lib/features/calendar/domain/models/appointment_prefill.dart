import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/policies/custom_address_policy.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

part 'appointment_prefill.freezed.dart';

/// What the add-appointment sheet opens pre-filled with.
@freezed
abstract class AppointmentPrefill with _$AppointmentPrefill {
  const factory AppointmentPrefill({
    ClientRecord? client,

    /// True when the job's address was not the client's, so the sheet opens on
    /// the address field rather than the client-address pill.
    @Default(false) bool useCustomAddress,

    /// Canonical, as stored; the sheet renders the display spelling.
    @Default('') String address,
    @Default('') String title,
    @Default('') String notes,
    @Default('') String materialsNeeded,

    /// Resolved against the live roster by the sheet — only crew still
    /// assignable carries over, so a disabled person can't be put on a new job.
    @Default(<String>[]) List<String> employeeIds,

    /// Seeds the end time when a start is picked (see `setDurationMinutes`);
    /// null keeps the form's plain default.
    int? durationMinutes,
  }) = _AppointmentPrefill;

  const AppointmentPrefill._();

  /// A repeat booking of [source].
  factory AppointmentPrefill.bookAgain(
    AppointmentRecord source, {
    required ClientRecord client,
  }) => AppointmentPrefill(
    client: client,
    useCustomAddress: usesCustomAddress(
      appointmentAddress: source.address,
      client: client,
    ),
    address: source.address,
    title: source.title,
    notes: source.notes,
    materialsNeeded: source.materialsNeeded,
    employeeIds: source.employeeIds,
    durationMinutes: _durationOf(source),
  );

  /// A timed window inside one day has a length worth carrying; an all-day
  /// block or a wide span does not.
  static int? _durationOf(AppointmentRecord source) {
    if (source.isAllDay) return null;
    final minutes = source.endTime.difference(source.startTime).inMinutes;
    return minutes > 0 && minutes < Duration.minutesPerDay ? minutes : null;
  }
}
