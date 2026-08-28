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

/// True when [raw] means the visit was called off.
bool isCancelledStatusRaw(String raw) => raw.toLowerCase() == 'cancelled';

/// True when [raw] means the job was finished, not cancelled.
bool isCompletedStatusRaw(String raw) =>
    isTerminalStatusRaw(raw) && !isCancelledStatusRaw(raw);
