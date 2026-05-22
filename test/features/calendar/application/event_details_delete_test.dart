import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _ThrowingRepo implements AppointmentsRepository {
  @override
  Future<void> deleteAppointment(String id) async {
    throw Exception('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  test(
    'deleteAppointment returns the error when the repository throws',
    () async {
      final container = ProviderContainer(
        overrides: [
          appointmentsRepositoryProvider.overrideWithValue(_ThrowingRepo()),
        ],
      );
      addTearDown(container.dispose);

      final appointment = AppointmentRecord(
        id: 'a1',
        startTime: DateTime(2026, 6, 6, 9),
        endTime: DateTime(2026, 6, 6, 10),
      );
      final provider = eventDetailsControllerProvider(appointment);
      // AutoDispose family: keep state alive across reads (testing.md).
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);

      final error = await container
          .read(provider.notifier)
          .deleteAppointment(appointment);

      expect(error, isNotNull);
      expect(error.toString(), contains('boom'));
    },
  );
}
