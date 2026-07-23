import 'package:flutter/foundation.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Result of `EventDetailsController.save`; widget switches for success/failure notice.
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

/// Result of status setters; sealed so call sites handle [EventDetailsActionBusy].
sealed class EventDetailsActionOutcome {
  const EventDetailsActionOutcome();
}

/// The status write committed.
class EventDetailsActionOk extends EventDetailsActionOutcome {
  const EventDetailsActionOk();
}

/// Skipped because another action held the busy flag; nothing written.
class EventDetailsActionBusy extends EventDetailsActionOutcome {
  const EventDetailsActionBusy();
}

class EventDetailsActionFailed extends EventDetailsActionOutcome {
  const EventDetailsActionFailed(this.error);
  final Object error;
}

/// Family key for `eventDetailsControllerProvider`; keys by id alone for identity stability.
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
