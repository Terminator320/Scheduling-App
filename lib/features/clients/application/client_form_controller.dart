import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// Outcome of a client add/update. The forms map this to notices or navigation.
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

/// CRUD orchestration shared by the add/edit/detail views. Handles the repository
/// write, the list refresh, and a best-effort phone-contact sync.
class ClientFormController extends Notifier<ClientFormActivity> {
  @override
  ClientFormActivity build() => const ClientFormActivity();

  /// Persists a new client. State resets in the `finally` block because this provider
  /// is shared with the detail pane in the split layout.
  Future<ClientSaveOutcome> addClient(ClientRecord client) async {
    // Bail out early if we're offline — Firestore writes block until the server acks,
    // so the button would just spin until reconnect (CLI-ADD maps the exception).
    if (ref.read(isOfflineProvider)) {
      return const ClientSaveFailed(SocketException('offline'));
    }
    // Resolve dependencies before the first await — in Riverpod 3, a disposed notifier's
    // Ref throws if you read it after that point.
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
    // Bail out early if we're offline (the edit form shows the CLI-SAVE notice).
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
