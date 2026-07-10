import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// In-memory [SecureStorageService] so the cache round-trip is exercised
/// without the platform Keychain/keystore method channel.
class _InMemorySecureStorage extends SecureStorageService {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

void main() {
  late _InMemorySecureStorage storage;
  late AuthCache cache;

  setUp(() {
    storage = _InMemorySecureStorage();
    cache = AuthCache(storage: storage);
  });

  const uid = 'uid-1';
  const record = EmployeeRecord(
    id: 'doc-1',
    uid: uid,
    name: 'Alex',
    color: Color(0xFF6366F1),
    status: 'active',
  );

  test('loadIfMatch round-trips a saved record for the same uid', () async {
    await cache.save(record);
    expect(await cache.loadIfMatch(uid), record);
  });

  test('loadIfMatch returns null when the uid does not match', () async {
    await cache.save(record);
    expect(await cache.loadIfMatch('other-uid'), isNull);
  });

  test('loadIfMatch returns null when nothing is cached', () async {
    expect(await cache.loadIfMatch(uid), isNull);
  });

  test('loadIfMatch returns null when the stored docId is empty', () async {
    await storage.write(SecureStorageKeys.cacheUid, uid);
    await storage.write(SecureStorageKeys.cacheDocId, '');
    expect(await cache.loadIfMatch(uid), isNull);
  });

  test('role is never cached: the restored record keeps the default', () async {
    await cache.save(record);
    final loaded = await cache.loadIfMatch(uid);
    expect(loaded!.role, 'employee');
  });

  test('clear removes the cached identity', () async {
    await cache.save(record);
    await cache.clear();
    expect(await cache.loadIfMatch(uid), isNull);
  });
}
