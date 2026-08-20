import 'package:cloud_firestore/cloud_firestore.dart';

/// Cursor advance for [pageToCap] — builds the query for the page after [last].
typedef PageCursor =
    Query<Map<String, dynamic>> Function(
      Query<Map<String, dynamic>> query,
      QueryDocumentSnapshot<Map<String, dynamic>> last,
    );

/// Reads [base] page by page until the collection runs out or [cap] documents
/// have been collected, calling [onCapReached] when it stops at the cap.
///
/// The three parts are one mechanism and none of them is optional. Paging is
/// what stops a single snapshot truncating the answer at one page; the cap is
/// what stops the loop walking the whole collection as it grows; the warn the
/// caller raises from [onCapReached] is what makes a truncation visible in
/// Crashlytics instead of silently hiding rows from search, the filter chips
/// and the lists that read them. A bounded read added here without a warn, or
/// a ceiling swapped for an unbounded `while (true)`, reintroduces a failure
/// nobody reports.
///
/// [advance] defaults to `startAfterDocument`; pass one only for a cursor the
/// query's `orderBy` fields have to spell out by value.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> pageToCap(
  Query<Map<String, dynamic>> base, {
  required int pageSize,
  required int cap,
  required void Function() onCapReached,
  PageCursor advance = startAfterLastDocument,
}) async {
  final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  var query = base.limit(pageSize);
  while (true) {
    final snapshot = await query.get();
    docs.addAll(snapshot.docs);
    if (docs.length >= cap) {
      onCapReached();
      break;
    }
    if (snapshot.docs.length < pageSize) break;
    query = advance(query, snapshot.docs.last);
  }
  return docs;
}

/// Default [pageToCap] cursor — the last document of the page just read.
Query<Map<String, dynamic>> startAfterLastDocument(
  Query<Map<String, dynamic>> query,
  QueryDocumentSnapshot<Map<String, dynamic>> last,
) => query.startAfterDocument(last);
