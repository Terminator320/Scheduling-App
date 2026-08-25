import 'package:flutter/foundation.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Result of `EventDetailsController.save`. The widget switches on this to
/// show a success or failure notice.
sealed class EventDetailsSaveOutcome {
  const EventDetailsSaveOutcome();
}

class EventDetailsInvalid extends EventDetailsSaveOutcome {
  const EventDetailsInvalid();
}

/// A save the reentrancy guard SKIPPED, distinct from one the validator
/// rejected — the save-family sibling of [EventDetailsActionBusy], which the
/// status setters and the delete already return. Surfaces nothing.
class EventDetailsSaveBusy extends EventDetailsSaveOutcome {
  const EventDetailsSaveBusy();
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

/// The save found a scheduling clash. Not an error — the widget asks the user
/// whether to push through, then calls `save(..., forceBusy: true)`.
class EventDetailsBusyEmployees extends EventDetailsSaveOutcome {
  const EventDetailsBusyEmployees({
    required this.busyEmployees,
    required this.start,
    required this.end,
  });

  final List<EmployeeRecord> busyEmployees;
  final DateTime start;
  final DateTime end;
}

/// Result of the status setters. Sealed so call sites are forced to handle
/// [EventDetailsActionBusy].
sealed class EventDetailsActionOutcome {
  const EventDetailsActionOutcome();
}

/// The status write committed.
class EventDetailsActionOk extends EventDetailsActionOutcome {
  const EventDetailsActionOk();
}

/// Skipped because another action already held the busy flag — nothing was written.
class EventDetailsActionBusy extends EventDetailsActionOutcome {
  const EventDetailsActionBusy();
}

class EventDetailsActionFailed extends EventDetailsActionOutcome {
  const EventDetailsActionFailed(this.error);
  final Object error;
}

/// Family key for `eventDetailsControllerProvider`. Keys off the id alone,
/// so identity stays stable.
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
