import 'package:cloud_firestore/cloud_firestore.dart';

/// Builds the next page query after [last].
typedef PageCursor =
    Query<Map<String, dynamic>> Function(
      Query<Map<String, dynamic>> query,
      QueryDocumentSnapshot<Map<String, dynamic>> last,
    );

/// Reads pages up to [cap] and warns only when extra docs were left behind.
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
    // A short page means the collection ran out.
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
