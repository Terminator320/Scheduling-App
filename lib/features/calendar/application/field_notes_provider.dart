import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/field_note.dart';

/// One job's crew notes, oldest first.
///
/// autoDispose and keyed by appointment id: the thread is read when a detail
/// sheet opens and is not worth holding once it closes.
final appointmentFieldNotesProvider = FutureProvider.autoDispose
    .family<List<FieldNote>, String>((ref, appointmentId) async {
      if (appointmentId.isEmpty) return const [];
      return await ref
          .watch(appointmentsRepositoryProvider)
          .fetchFieldNotes(appointmentId);
    });
