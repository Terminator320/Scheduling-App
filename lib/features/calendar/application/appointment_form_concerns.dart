import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart' show immutable, protected;

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// The appointment-form fields shared by `AddEventState` and
/// `EventDetailsState`; [AppointmentFormConcerns] reads the two freezed
/// states through this interface.
abstract interface class AppointmentFormFields {
  ClientRecord? get selectedClient;
  List<ClientRecord> get clientResults;
  bool get isSearchingClient;
  bool get useCustomAddress;
  List<EmployeeRecord> get selectedEmployees;
  Map<String, AppointmentFormError> get errors;
}

/// One shared-form state change, applied by each controller's
/// [AppointmentFormConcerns.applyFormUpdate] adapter (freezed `copyWith`
/// can't be expressed over a common interface). A null field means "leave
/// unchanged".
@immutable
class AppointmentFormUpdate {
  const AppointmentFormUpdate({
    this.clientResults,
    this.isSearchingClient,
    this.selectedClient,
    this.clearSelectedClient = false,
    this.useCustomAddress,
    this.selectedEmployees,
    this.errors,
    this.pendingImages,
  });

  final List<ClientRecord>? clientResults;
  final bool? isSearchingClient;

  /// Non-null when the user picked a client from the search results.
  final ClientRecord? selectedClient;

  /// True when the user explicitly removed the selected client.
  final bool clearSelectedClient;

  final bool? useCustomAddress;
  final List<EmployeeRecord>? selectedEmployees;
  final Map<String, AppointmentFormError>? errors;

  /// Locally picked, not-yet-uploaded photos.
  final List<File>? pendingImages;
}

/// The form behavior shared verbatim by `AddEventController` and
/// `EventDetailsController`: client search/select/clear, the custom-address
/// toggle, the employee picker and the capped local photo picks. Each
/// controller adapts writes to its own freezed state via [applyFormUpdate]
/// and exposes its image lists via [usedImageCount]/[pendingImages].
mixin AppointmentFormConcerns<StateT extends AppointmentFormFields>
    on Notifier<StateT> {
  static const int maxImagesPerAppointment = 10;

  /// Adapter over the concrete state's `copyWith` for the shared fields.
  @protected
  StateT applyFormUpdate(StateT current, AppointmentFormUpdate update);

  /// Photos already attached to this form, counted against the cap — the add
  /// flow counts only local picks, the edit flow also counts the photos
  /// already stored on the visit.
  @protected
  int get usedImageCount;

  /// The locally picked, not-yet-uploaded photos.
  @protected
  List<File> get pendingImages;

  void _apply(AppointmentFormUpdate update) =>
      state = applyFormUpdate(state, update);

  Future<void> searchClients(String query) async {
    final trimmed = query.trim();
    if (!ClientSearchPolicy.shouldSearch(trimmed)) {
      _apply(
        const AppointmentFormUpdate(
          clientResults: [],
          isSearchingClient: false,
        ),
      );
      return;
    }
    _apply(const AppointmentFormUpdate(isSearchingClient: true));
    // Resolved before the await: the sheet can be dismissed mid-search, and
    // using the Ref of a disposed notifier throws in Riverpod 3.
    final logger = ref.read(loggerProvider);
    final clientsRepo = ref.read(clientsRepositoryProvider);
    try {
      final results = await clientsRepo.searchClients(trimmed);
      if (!ref.mounted) return;
      _apply(
        AppointmentFormUpdate(clientResults: results, isSearchingClient: false),
      );
    } catch (e, st) {
      logger.warn('searchClients failed', e, st);
      if (!ref.mounted) return;
      _apply(const AppointmentFormUpdate(isSearchingClient: false));
    }
  }

  void selectClient(ClientRecord client) {
    _apply(
      AppointmentFormUpdate(
        selectedClient: client,
        clientResults: const [],
        useCustomAddress:
            client.noFixedAddress || client.address.trim().isEmpty,
        errors: withoutKey(state.errors, 'client'),
      ),
    );
  }

  void clearClient() {
    _apply(
      const AppointmentFormUpdate(
        clearSelectedClient: true,
        clientResults: [],
        useCustomAddress: false,
      ),
    );
  }

  void setUseCustomAddress({required bool value}) {
    _apply(AppointmentFormUpdate(useCustomAddress: value));
  }

  void toggleEmployee(EmployeeRecord employee) {
    final next = [...state.selectedEmployees];
    final idx = next.indexWhere((e) => e.id == employee.id);
    if (idx >= 0) {
      next.removeAt(idx);
    } else {
      next.add(employee);
    }
    _apply(
      AppointmentFormUpdate(
        selectedEmployees: next,
        errors: next.isEmpty
            ? state.errors
            : withoutKey(state.errors, 'employees'),
      ),
    );
  }

  void addImages(List<File> files) {
    final remaining = maxImagesPerAppointment - usedImageCount;
    if (remaining <= 0) return;
    final accepted = files.take(remaining).toList();
    _apply(
      AppointmentFormUpdate(pendingImages: [...pendingImages, ...accepted]),
    );
  }

  /// Drops the pending (not-yet-uploaded) photo at [index]; the controllers
  /// expose it under their historical names (`removeImage` /
  /// `removeNewImage`).
  @protected
  void removePendingImageAt(int index) {
    final next = [...pendingImages]..removeAt(index);
    _apply(AppointmentFormUpdate(pendingImages: next));
  }
}
