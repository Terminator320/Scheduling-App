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
    final matchesClient =
        normalizedQuery.isNotEmpty &&
        ClientSearchPolicy.normalize(
          (data['clientName'] ?? '').toString(),
        ).contains(normalizedQuery);
    final matchesEmployee =
        normalizedQuery.isNotEmpty &&
        firestoreStringList(data['employeeNames']).any(
          (e) => ClientSearchPolicy.normalize(e).contains(normalizedQuery),
        );
    final matchesPhone =
        queryDigits.isNotEmpty &&
        ClientSearchPolicy.digitsOnly(
          (data['clientPhone'] ?? '').toString(),
        ).contains(queryDigits);
    if (!matchesClient && !matchesEmployee && !matchesPhone) continue;
    matches.add(AppointmentRecord.fromMap(doc.id, data));
  }
  return matches;
}
