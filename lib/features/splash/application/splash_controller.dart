import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

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

final splashDestinationProvider = FutureProvider<SplashDestination>((
  ref,
) async {
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) return const SplashGoToLogin();

  final employeesRepo = ref.watch(employeesRepositoryProvider);
  final logger = ref.read(loggerProvider);
  final UserUidMatch? match;
  try {
    match = await retryAsync(
      () => employeesRepo.findUserByUid(user.uid),
      delays: const [Duration(milliseconds: 500), Duration(milliseconds: 1500)],
      onRetry: (attempt, e, st) =>
          logger.warn('splash findUserByUid retry $attempt', e, st),
    );
  } catch (e, st) {
    logger.warn('splash findUserByUid failed after retries', e, st);
    rethrow;
  }
  if (match == null) {
    await auth.signOut();
    return const SplashGoToLogin();
  }

  final employee = EmployeeRecord.fromMap(match.id, match.data);
  if (!employee.isActive) {
    await auth.signOut();
    await AuthCache().clear();
    return const SplashGoToLogin();
  }
  unawaited(AuthCache().save(employee));
  return SplashGoToCalendar(isAdmin: employee.isAdmin, employeeId: employee.id);
});
