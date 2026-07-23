import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// Outcome of client add/update; mapped to notices/navigation by the forms.
sealed class ClientSaveOutcome {
  const ClientSaveOutcome();
}

class ClientSaved extends ClientSaveOutcome {
  const ClientSaved(this.client);
  final ClientRecord client;
}

class ClientSaveFailed extends ClientSaveOutcome {
  const ClientSaveFailed(this.error);
  final Object error;
}

/// Outcome of a client delete.
sealed class ClientDeleteOutcome {
  const ClientDeleteOutcome();
}

class ClientDeleted extends ClientDeleteOutcome {
  const ClientDeleted();
}

class ClientDeleteFailed extends ClientDeleteOutcome {
  const ClientDeleteFailed(this.error);
  final Object error;
}

/// Busy flags for the client forms driving Save spinner and Delete button state.
@immutable
class ClientFormActivity {
  const ClientFormActivity({this.isSaving = false, this.isDeleting = false});

  final bool isSaving;
  final bool isDeleting;

  ClientFormActivity copyWith({bool? isSaving, bool? isDeleting}) {
    return ClientFormActivity(
      isSaving: isSaving ?? this.isSaving,
      isDeleting: isDeleting ?? this.isDeleting,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClientFormActivity &&
      other.isSaving == isSaving &&
      other.isDeleting == isDeleting;

  @override
  int get hashCode => Object.hash(isSaving, isDeleting);
}

/// CRUD orchestration shared by add/edit/detail views; repository write, list refresh, and best-effort phone-contact sync.
class ClientFormController extends Notifier<ClientFormActivity> {
  @override
  ClientFormActivity build() => const ClientFormActivity();

  /// Persists new client; state resets in finally since this provider is shared with detail pane (split layout).
  Future<ClientSaveOutcome> addClient(ClientRecord client) async {
    // Fail fast offline; Firestore writes block until server ack, so button would spin until reconnect (CLI-ADD maps exception).
    if (ref.read(isOfflineProvider)) {
      return const ClientSaveFailed(SocketException('offline'));
    }
    // Resolve dependencies before first await (disposed notifier Ref throws in Riverpod 3).
    final repo = ref.read(clientsRepositoryProvider);
    final refresh = ref.read(clientsRefreshProvider.notifier);
    final logger = ref.read(loggerProvider);
    state = state.copyWith(isSaving: true);
    try {
      final saved = await repo.addClient(client);
      refresh.bump();
      return ClientSaved(saved);
    } catch (e, st) {
      logger.warn('CLI-ADD addClient failed', e, st);
      return ClientSaveFailed(e);
    } finally {
      if (ref.mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// Persists edit and mirrors to phone contact (best-effort, never blocks/fails the save).
  Future<ClientSaveOutcome> updateClient(ClientRecord client) async {
    // Fail fast offline (CLI-SAVE notice on edit form).
    if (ref.read(isOfflineProvider)) {
      return const ClientSaveFailed(SocketException('offline'));
    }
    // Resolved before first await (see addClient).
    final repo = ref.read(clientsRepositoryProvider);
    final refresh = ref.read(clientsRefreshProvider.notifier);
    final logger = ref.read(loggerProvider);
    final linkStore = ref.read(contactLinkStoreProvider);
    state = state.copyWith(isSaving: true);
    try {
      await repo.updateClient(client);
      refresh.bump();
      await updateLinkedPhoneContact(
        linkStore: linkStore,
        logger: logger,
        client: client,
      );
      return ClientSaved(client);
    } catch (e, st) {
      logger.warn('CLI-SAVE updateClient failed', e, st);
      return ClientSaveFailed(e);
    } finally {
      if (ref.mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// Deletes client, drops device-local phone-contact link (best-effort), and bumps list refresh.
  Future<ClientDeleteOutcome> deleteClient(String clientId) async {
    // Resolved before first await.
    final repo = ref.read(clientsRepositoryProvider);
    final refresh = ref.read(clientsRefreshProvider.notifier);
    final logger = ref.read(loggerProvider);
    final linkStore = ref.read(contactLinkStoreProvider);
    state = state.copyWith(isDeleting: true);
    try {
      await repo.deleteClient(clientId);
      try {
        await linkStore.unlink(clientId);
      } catch (e, st) {
        logger.warn('CLI-DEL contact unlink failed', e, st);
      }
      refresh.bump();
      if (ref.mounted) state = state.copyWith(isDeleting: false);
      return const ClientDeleted();
    } catch (e, st) {
      logger.warn('CLI-DEL deleteClient failed', e, st);
      if (ref.mounted) state = state.copyWith(isDeleting: false);
      return ClientDeleteFailed(e);
    }
  }
}

final clientFormControllerProvider =
    NotifierProvider.autoDispose<ClientFormController, ClientFormActivity>(
      ClientFormController.new,
    );
