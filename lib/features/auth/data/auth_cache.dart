import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Caches the minimum information needed to skip the full splash sequence on
/// the next cold start (uid, Firestore doc id, display name, employee colour).
///
/// `isAdmin` and `status` are intentionally NOT cached — they are security
/// boundaries and must be re-read from Firestore on every launch via
/// `EmployeesRepository.findUserByUid` (CLAUDE.md invariant). The cache only
/// tells callers "a Firestore lookup is worth attempting because the uid
/// matches"; it never grants permissions on its own.
class AuthCache {
  static const _kUid = 'uc_uid';
  static const _kDocId = 'uc_doc_id';
  static const _kColorValue = 'uc_color_value';
  static const _kName = 'uc_name';

  Future<void> save(EmployeeRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, record.uid);
    await prefs.setString(_kDocId, record.id);
    await prefs.setInt(_kColorValue, record.color.toARGB32());
    await prefs.setString(_kName, record.name);
  }

  /// Returns a cached record only when the stored uid matches [uid].
  /// Returns null on any mismatch, missing key, or parse error.
  Future<EmployeeRecord?> loadIfMatch(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kUid) != uid) return null;
    final docId = prefs.getString(_kDocId);
    if (docId == null || docId.isEmpty) return null;
    return EmployeeRecord(
      id: docId,
      uid: uid,
      name: prefs.getString(_kName) ?? '',
      color: Color(prefs.getInt(_kColorValue) ?? Colors.blue.toARGB32()),
      status: 'active',
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kDocId);
    await prefs.remove(_kColorValue);
    await prefs.remove(_kName);
  }
}
