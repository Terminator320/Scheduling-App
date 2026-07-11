import 'package:flutter/foundation.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Result of `EventDetailsController.save`. The widget layer switches on this
/// sealed family to compose the success/failure notice.
sealed class EventDetailsSaveOutcome {
  const EventDetailsSaveOutcome();
}

class EventDetailsInvalid extends EventDetailsSaveOutcome {
  const EventDetailsInvalid();
}

class EventDetailsSaved extends EventDetailsSaveOutcome {
  const EventDetailsSaved(
    this.appointment, {
    this.futureBookings = 0,
    this.removedBookings = 0,
    this.updatedSiblings = 0,
  });
  final AppointmentRecord appointment;

  /// Pre-booked repeat occurrences created alongside the save.
  final int futureBookings;

  /// Old future occurrences deleted by a series rewrite.
  final int removedBookings;

  /// Future series visits the edit was propagated to (apply-to-all).
  final int updatedSiblings;
}

class EventDetailsFailed extends EventDetailsSaveOutcome {
  const EventDetailsFailed(this.error);
  final Object error;
}

/// Family key for `eventDetailsControllerProvider`: carries the record the
/// sheet opened with, but keys provider identity by the appointment id alone,
/// so provider lookups don't deep-compare the whole freezed record on every
/// rebuild and two snapshots of the same visit share one controller.
@immutable
class EventDetailsKey {
  const EventDetailsKey(this.appointment);

  final AppointmentRecord appointment;

  @override
  bool operator ==(Object other) =>
      other is EventDetailsKey && other.appointment.id == appointment.id;

  @override
  int get hashCode => appointment.id.hashCode;
}
