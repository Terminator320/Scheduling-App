import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:scheduling/core/images/appointment_image_loader.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';

class DeviceDeregistrationDeps {
  DeviceDeregistrationDeps({
    required this.logger,
    required this.push,
    required this.presence,
    required this.liveActivity,
    required this.imageLoader,
    required this.clients,
    required this.appointments,
  });

  /// Builds dependencies from any Riverpod read function.
  factory DeviceDeregistrationDeps.from(
    T Function<T>(ProviderListenable<T>) read,
  ) => DeviceDeregistrationDeps(
    logger: read(loggerProvider),
    push: read(pushRegistrationControllerProvider),
    presence: read(presenceSyncControllerProvider),
    liveActivity: read(liveActivityRegistrationControllerProvider),
    imageLoader: read(appointmentImageLoaderProvider),
    clients: read(clientsRepositoryProvider),
    appointments: read(appointmentsRepositoryProvider),
  );

  final AppLogger logger;
  final PushRegistrationController push;
  final PresenceSyncController presence;
  final LiveActivityRegistrationController liveActivity;
  final AppointmentImageLoader imageLoader;
  final ClientsRepository clients;
  final AppointmentsRepository appointments;
}

/// Best-effort device teardown before credentials are revoked.
Future<void> deregisterThisDevice(DeviceDeregistrationDeps deps) async {
  final logger = deps.logger;
  final push = deps.push;
  final presence = deps.presence;
  final liveActivity = deps.liveActivity;
  // Hoisted so teardown-time reads fail before any awaited steps.
  final imageLoader = deps.imageLoader;
  // Hoisted for the same teardown-time read behavior.
  final clients = deps.clients;
  final appointments = deps.appointments;

  await _step(logger, 'push de-registration', push.unregisterCurrentDevice);
  await _step(logger, 'presence de-registration', presence.unregister);
  await _step(logger, 'liveActivity de-registration', liveActivity.unregister);

  // Local caches clear last because credential-dependent unregisters come first.
  await _step(logger, 'imageCache de-registration', imageLoader.clear);
  // Repository search windows also live for the process.
  await _step(logger, 'client cache clear', () async => clients.clearCaches());
  await _step(
    logger,
    'appointment cache clear',
    () async => appointments.clearCaches(),
  );
}

/// Restores server-side registrations after a failed account exit.
Future<void> restoreThisDevice(DeviceDeregistrationDeps deps) async {
  final logger = deps.logger;
  await _step(logger, 'restore push', deps.push.sync);
  await _step(logger, 'restore presence', deps.presence.sync);
  await _step(logger, 'restore liveActivity', deps.liveActivity.sync);
}

/// One isolated best-effort step, shared by the teardown and its rollback.
Future<void> _step(
  AppLogger logger,
  String label,
  Future<void> Function() run,
) async {
  try {
    await run();
  } catch (e, st) {
    logger.warn('ACCOUNT-EXIT $label failed', e, st);
  }
}

/// Resolves the signed-in user's `users` doc id without throwing.
Future<String?> resolveUserDocId({
  required Ref ref,
  required FirebaseAuth auth,
  required AppLogger logger,
  required String tag,
}) async {
  final uid = auth.currentUser?.uid;
  if (uid == null) return null;
  try {
    final match = await ref
        .read(employeesRepositoryProvider)
        .findUserByUid(uid);
    return match?.id;
  } catch (e, st) {
    logger.warn('$tag resolve users doc failed', e, st);
    return null;
  }
}
