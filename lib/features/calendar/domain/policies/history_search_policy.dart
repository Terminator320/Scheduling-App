import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

/// One raw Firestore document from the history scan window, before any record
/// is built for it.
typedef RawHistoryDoc = ({String id, Map<String, dynamic> data});

/// The input [matchHistoryDocs] runs over — a scan window and the query.
///
/// A single object because this crosses the `compute` isolate boundary, which
/// takes exactly one argument.
class HistorySearchScan {
  const HistorySearchScan({required this.docs, required this.query});

  final List<RawHistoryDoc> docs;
  final String query;
}

/// A pre-normalized searchable projection of one appointment.
///
/// The loaded-page filter builds these once per page change and matches them
/// per keystroke, exactly as `ClientSearchEntry` does on the clients side.
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
///
/// **The one owner of the appointment-search predicate.** It was spelled twice
/// — here, over the raw Firestore map for the debounced server scan, and in
/// `appointment_history_view.dart` over the loaded page. Those are the SAME
/// search at two layers: add a field to one and the results visibly change
/// when the debounce settles, with nothing logged. The clients side already
/// learned this and extracted `ClientSearchPolicy.entryMatches`; this is its
/// twin, and both call sites route through it.
///
/// [queryText] and [queryDigits] arrive pre-normalized because both callers
/// normalize once per query rather than once per row.
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
///
/// Product behaviour, not storage: it lived at the bottom of
/// `firebase_appointments_repository.dart` beside the Firestore plumbing, which
/// is the same split `ClientSearchPolicy` already resolved the other way — the
/// matching rules there sit in `domain/policies/` and the repository calls
/// into them. This is that file's sibling for appointments, and putting it here
/// is what lets it be read (and tested) without a Firestore handle in scope.
///
/// **Parse list fields through [firestoreStringList], never a private copy.**
/// This reads `employeeNames` off the RAW map before any record exists, so a
/// second spelling that accepted less would silently reject documents the
/// record itself would have matched — a search that quietly stops finding a
/// crew member, with nothing logged.
List<AppointmentRecord> matchHistoryDocs(HistorySearchScan scan) {
  final normalizedQuery = ClientSearchPolicy.normalize(scan.query);
  final queryDigits = ClientSearchPolicy.digitsOnly(scan.query);

  final matches = <AppointmentRecord>[];
  for (final doc in scan.docs) {
    // The three fields the filter reads come straight off the raw map, and
    // `fromMap` is paid only for a document that survives. The scan window is
    // `_historySearchScanLimit` documents and a query keeps a handful, so
    // building a full record first meant ~20 map reads, four date conversions,
    // two list parses and a freezed constructor for every document rejected.
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
