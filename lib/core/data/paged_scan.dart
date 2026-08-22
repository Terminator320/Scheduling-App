import 'package:cloud_firestore/cloud_firestore.dart';

/// Cursor advance for [pageToCap] — builds the query for the page after [last].
typedef PageCursor =
    Query<Map<String, dynamic>> Function(
      Query<Map<String, dynamic>> query,
      QueryDocumentSnapshot<Map<String, dynamic>> last,
    );

/// Reads [base] page by page until the collection runs out or more than [cap]
/// documents exist, returning at most [cap] of them and calling [onCapReached]
/// only when documents were actually left behind.
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
/// One document past the cap is read on purpose. A collection that is exactly
/// [cap] long hides nothing, and warning about it sends someone hunting a
/// truncation that never happened — reading one more is the only way to tell
/// the two apart, and it costs a single extra round trip in the cap case
/// alone, which is already the degraded one.
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
  var cursor = base;
  while (true) {
    final remaining = cap + 1 - docs.length;
    final pageLimit = remaining < pageSize ? remaining : pageSize;
    if (pageLimit <= 0) break;
    final snapshot = await cursor.limit(pageLimit).get();
    docs.addAll(snapshot.docs);
    // A short page means the collection ran out, so nothing was left behind
    // whatever the count reached.
    if (snapshot.docs.length < pageLimit) break;
    cursor = advance(cursor, snapshot.docs.last);
  }
  if (docs.length > cap) {
    onCapReached();
    return docs.sublist(0, cap);
  }
  return docs;
}

/// Default [pageToCap] cursor — the last document of the page just read.
Query<Map<String, dynamic>> startAfterLastDocument(
  Query<Map<String, dynamic>> query,
  QueryDocumentSnapshot<Map<String, dynamic>> last,
) => query.startAfterDocument(last);
