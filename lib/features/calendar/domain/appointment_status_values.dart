/// The raw stored `status` strings that mean a job is closed.
///
/// **One owner, deliberately.** "Terminal appointment status" previously had
/// four independent definitions and one of them had drifted: the History
/// query's `whereIn` listed only `done`/`cancelled`, so a legacy `completed`
/// doc rendered as Done on its card, was correctly skipped by the conflict
/// check, and was invisible in History and history search — with no error
/// anywhere.
///
/// `completed` is a legacy alias for `done`. `firestore.rules` has allowed only
/// `pending|in_progress|done|cancelled` since it was written, so any such doc
/// predates the rules; it stays here because three of the four owners already
/// believed those docs exist, and reading one is free while missing one is
/// silent.
///
/// This module is deliberately **pure** — no Material, no Firestore — so the
/// model layer (`AppointmentRecord.isClosed`) and the repository's Firestore
/// query can share it. `AppointmentStatus.isTerminal` in
/// `shared/widgets/feedback/status_chip.dart` is the enum-level mirror, pinned
/// against this set by `appointment_status_values_test.dart`.
library;

const Set<String> terminalStatusRawValues = {'done', 'completed', 'cancelled'};

/// The same vocabulary as a list, for a Firestore `whereIn` constraint.
///
/// Derived rather than re-spelled — a second literal here is the exact drift
/// this module exists to end. Well inside the 30-value cap, and `whereIn`
/// ignores order.
final List<String> terminalStatusQueryValues = List.unmodifiable(
  terminalStatusRawValues,
);

/// True when [raw] is a stored status meaning the job is closed.
bool isTerminalStatusRaw(String raw) =>
    terminalStatusRawValues.contains(raw.toLowerCase());
