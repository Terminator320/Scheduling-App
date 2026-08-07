import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart'
    show immutable, protected;

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Shared appointment-form fields read through this interface by [AppointmentFormConcerns].
abstract interface class AppointmentFormFields {
  ClientRecord? get selectedClient;
  List<ClientRecord> get clientResults;
  bool get isSearchingClient;
  bool get useCustomAddress;
  List<EmployeeRecord> get selectedEmployees;
  Map<String, AppointmentFormError> get errors;
}

/// One form state change, applied through each controller's adapter. A null
/// field just means that part of the state is unchanged.
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

/// Shared form behavior for searching, selecting, toggling, picking, and
/// clearing. Each controller adapts it to its own state.
mixin AppointmentFormConcerns<StateT extends AppointmentFormFields>
    on Notifier<StateT> {
  static const int maxImagesPerAppointment = 10;

  /// Adapter over the concrete state's `copyWith` for the shared fields.
  @protected
  StateT applyFormUpdate(StateT current, AppointmentFormUpdate update);

  /// Photos already attached to this form, counted against the cap.
  @protected
  int get usedImageCount;

  /// The locally picked, not-yet-uploaded photos.
  @protected
  List<File> get pendingImages;

  void _apply(AppointmentFormUpdate update) =>
      state = applyFormUpdate(state, update);

  /// Request id to prevent stale reads from overwriting fresh results.
  int _searchRequestId = 0;

  Future<void> searchClients(String query) async {
    final trimmed = query.trim();
    if (!ClientSearchPolicy.shouldSearch(trimmed)) {
      _searchRequestId++;
      _apply(
        const AppointmentFormUpdate(
          clientResults: [],
          isSearchingClient: false,
        ),
      );
      return;
    }
    final requestId = ++_searchRequestId;
    _apply(const AppointmentFormUpdate(isSearchingClient: true));
    // Resolve these before the await so they survive the sheet being dismissed (Riverpod 3).
    final logger = ref.read(loggerProvider);
    final clientsRepo = ref.read(clientsRepositoryProvider);
    try {
      final results = await clientsRepo.searchClients(trimmed);
      if (!ref.mounted || requestId != _searchRequestId) return;
      _apply(
        AppointmentFormUpdate(clientResults: results, isSearchingClient: false),
      );
    } catch (e, st) {
      logger.warn('searchClients failed', e, st);
      if (!ref.mounted || requestId != _searchRequestId) return;
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

  /// Drops the pending photo at [index] (exposed as removeImage/removeNewImage).
  @protected
  void removePendingImageAt(int index) {
    final next = [...pendingImages]..removeAt(index);
    _apply(AppointmentFormUpdate(pendingImages: next));
  }
}
