/// Raw stored statuses that mean an appointment is closed.
library;

const Set<String> terminalStatusRawValues = {'done', 'completed', 'cancelled'};

/// Terminal statuses as a Firestore `whereIn` list.
final List<String> terminalStatusQueryValues = List.unmodifiable(
  terminalStatusRawValues,
);

/// True when [raw] is a stored status meaning the job is closed.
bool isTerminalStatusRaw(String raw) =>
    terminalStatusRawValues.contains(raw.toLowerCase());

/// The two crew signals an assignee may put on an open job, as stored.
const Set<String> crewStatusRawValues = {'onMyWay', 'runningLate'};

/// True when [raw] means the visit was called off.
bool isCancelledStatusRaw(String raw) => raw.toLowerCase() == 'cancelled';

/// True when [raw] means the job was finished, not cancelled.
bool isCompletedStatusRaw(String raw) =>
    isTerminalStatusRaw(raw) && !isCancelledStatusRaw(raw);

/// Appointment states run pending → in_progress → done, plus cancelled.
enum AppointmentStatus {
  pending,
  inProgress,
  overdue,
  done,
  cancelled;

  /// Maps a stored status string to the enum. Unrecognized values default to pending.
  static AppointmentStatus fromRaw(String raw) => switch (raw.toLowerCase()) {
    'done' || 'completed' => done,
    'cancelled' => cancelled,
    'overdue' => overdue,
    'in_progress' || 'inprogress' => inProgress,
    _ => pending,
  };

  /// Pickable statuses (excludes display-only overdue).
  static const appointmentValues = [pending, inProgress, done];

  /// Normalizes a stored status to the allowlist — legacy, unknown, and overdue
  /// values all collapse to pending.
  static String storedRaw(String raw) {
    final status = fromRaw(raw);
    return status == overdue ? pending.raw : status.raw;
  }

  /// The stored raw string for this status.
  String get raw => switch (this) {
    inProgress => 'in_progress',
    overdue => throw StateError(
      'overdue is display-only; it has no stored raw',
    ),
    _ => name,
  };

  bool get isDone => this == done;
  bool get isCancelled => this == cancelled;

  /// Terminal states exit the active workflow.
  bool get isTerminal => isDone || isCancelled;
}
