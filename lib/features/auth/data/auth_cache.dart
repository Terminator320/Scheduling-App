import 'package:flutter/material.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Caches the signed-in employee's display identity (uid, doc id, name,
/// avatar color) at rest. Backed by [SecureStorageService] so the cached
/// identity is encrypted rather than sitting in plaintext SharedPreferences.
///
/// Role/`isAdmin` is deliberately never cached — that always comes from
/// Firestore (see the role-cache invariant).
class AuthCache {
  AuthCache({SecureStorageService? storage})
    : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  Future<void> save(EmployeeRecord record) async {
    await _storage.write(SecureStorageKeys.cacheUid, record.uid);
    await _storage.write(SecureStorageKeys.cacheDocId, record.id);
    await _storage.write(
      SecureStorageKeys.cacheColorValue,
      record.color.toARGB32().toString(),
    );
    await _storage.write(SecureStorageKeys.cacheName, record.name);
  }

  Future<EmployeeRecord?> loadIfMatch(String uid) async {
    if (await _storage.read(SecureStorageKeys.cacheUid) != uid) return null;
    final docId = await _storage.read(SecureStorageKeys.cacheDocId);
    if (docId == null || docId.isEmpty) return null;
    final colorValue = await _storage.read(SecureStorageKeys.cacheColorValue);
    return EmployeeRecord(
      id: docId,
      uid: uid,
      name: await _storage.read(SecureStorageKeys.cacheName) ?? '',
      color: Color(int.tryParse(colorValue ?? '') ?? Colors.blue.toARGB32()),
      status: 'active',
    );
  }

  Future<void> clear() async {
    await _storage.delete(SecureStorageKeys.cacheUid);
    await _storage.delete(SecureStorageKeys.cacheDocId);
    await _storage.delete(SecureStorageKeys.cacheColorValue);
    await _storage.delete(SecureStorageKeys.cacheName);
  }
}
