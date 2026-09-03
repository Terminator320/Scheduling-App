import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

/// One raw Firestore document from the history scan window, before any record
/// is built for it.
typedef RawHistoryDoc = ({String id, Map<String, dynamic> data});

/// The input [matchHistoryDocs] runs over — a scan window and the query.
class HistorySearchScan {
  const HistorySearchScan({required this.docs, required this.query});

  final List<RawHistoryDoc> docs;
  final String query;
}

/// A pre-normalized searchable projection of one appointment.
typedef HistorySearchEntry = ({
  String clientText,
  List<String> employeeTexts,
  String phoneDigits,
});

/// The projection [historyEntryMatches] runs over, from an already-built
/// record.
HistorySearchEntry historyEntryOf(AppointmentRecord appointment) => (
  clientText: ClientSearchPolicy.normalize(appointment.clientName),
  employeeTexts: [
    for (final e in appointment.employeeNames) ClientSearchPolicy.normalize(e),
  ],
  phoneDigits: ClientSearchPolicy.digitsOnly(appointment.clientPhone),
);

/// Whether [entry] matches an already-normalized query.
bool historyEntryMatches(
  HistorySearchEntry entry, {
  required String queryText,
  required String queryDigits,
}) {
  if (queryText.isEmpty && queryDigits.isEmpty) return false;
  if (queryText.isNotEmpty && entry.clientText.contains(queryText)) return true;
  if (queryText.isNotEmpty &&
      entry.employeeTexts.any((e) => e.contains(queryText))) {
    return true;
  }
  return queryDigits.isNotEmpty && entry.phoneDigits.contains(queryDigits);
}

/// Which appointments in a history scan window match [HistorySearchScan.query].
List<AppointmentRecord> matchHistoryDocs(HistorySearchScan scan) {
  final normalizedQuery = ClientSearchPolicy.normalize(scan.query);
  final queryDigits = ClientSearchPolicy.digitsOnly(scan.query);

  final matches = <AppointmentRecord>[];
  for (final doc in scan.docs) {
    // The three fields the filter reads come straight off the raw map, and
    // `fromMap` is paid only for a document that survives.
    final data = doc.data;
    final entry = (
      clientText: ClientSearchPolicy.normalize(
        (data['clientName'] ?? '').toString(),
      ),
      employeeTexts: [
        for (final e in firestoreStringList(data['employeeNames']))
          ClientSearchPolicy.normalize(e),
      ],
      phoneDigits: ClientSearchPolicy.digitsOnly(
        (data['clientPhone'] ?? '').toString(),
      ),
    );
    if (!historyEntryMatches(
      entry,
      queryText: normalizedQuery,
      queryDigits: queryDigits,
    )) {
      continue;
    }
    matches.add(AppointmentRecord.fromMap(doc.id, data));
  }
  return matches;
}
