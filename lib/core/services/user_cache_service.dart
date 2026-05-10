import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class UserCacheService {
  static const _kUid = 'uc_uid';
  static const _kDocId = 'uc_doc_id';
  static const _kColorValue = 'uc_color_value';
  static const _kName = 'uc_name';

  // isAdmin is intentionally NOT cached — it is a security boundary and must
  // always be verified from Firestore on startup.

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
      email: '',
      phone: '',
      color: Color(prefs.getInt(_kColorValue) ?? Colors.blue.toARGB32()),
      role: 'employee', // placeholder — caller must verify role from Firestore
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
