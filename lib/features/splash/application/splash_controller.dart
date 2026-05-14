import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// What the splash screen has decided to do once auth resolution finishes.
sealed class SplashDestination {
  const SplashDestination();
}

class SplashGoToLogin extends SplashDestination {
  const SplashGoToLogin();
}

class SplashGoToCalendar extends SplashDestination {
  const SplashGoToCalendar({required this.isAdmin, required this.employeeId});
  final bool isAdmin;
  final String employeeId;
}

/// Resolves the post-splash destination by:
/// 1. checking Firebase Auth for a current user;
/// 2. looking up that user's `users/{...}` doc via `EmployeesRepository`
///    (CLAUDE.md role-from-Firestore-only invariant);
/// 3. caching the resulting `EmployeeRecord` so the next cold start can
///    skip the splash entirely (see `main._resolveHome`).
final splashDestinationProvider = FutureProvider<SplashDestination>((ref) async {
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) return const SplashGoToLogin();

  final employeesRepo = ref.watch(employeesRepositoryProvider);
  final match = await employeesRepo.findUserByUid(user.uid);
  if (match == null) {
    await auth.signOut();
    return const SplashGoToLogin();
  }

  final employee = EmployeeRecord.fromMap(match.id, match.data);
  if (employee.isDisabled) {
    await auth.signOut();
    await AuthCache().clear();
    return const SplashGoToLogin();
  }
  unawaited(AuthCache().save(employee));
  return SplashGoToCalendar(
    isAdmin: employee.isAdmin,
    employeeId: employee.id,
  );
});
