import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// Outcome of a client add/update. The forms only map these to notices and
/// navigation; the persistence flow lives in [ClientFormController].
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

/// Busy flags for the client forms — drive the Save spinner / disabled
/// Delete button while a mutation is in flight.
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

/// Client CRUD orchestration shared by the add sheet, the edit form and the
/// detail view: repository write, [clientsRefreshProvider] bump (so the
/// paginated list refreshes) and the best-effort phone-contact sync, with a
/// typed outcome per operation. Validation stays in the widgets (via
/// `ClientFormValidator`); they map outcomes to notices/navigation.
class ClientFormController extends Notifier<ClientFormActivity> {
  @override
  ClientFormActivity build() => const ClientFormActivity();

  /// Persists a new client. [state] always resets in `finally`: this provider
  /// is shared with the detail pane, which keeps it alive in the split layout
  /// after the add sheet pops — a lingering `isSaving` would brick the next
  /// add/edit. The sheet pops in the same frame, so no double-tap window opens.
  Future<ClientSaveOutcome> addClient(ClientRecord client) async {
    // Resolve dependencies before the first await: the sheet can be dismissed
    // mid-save, and using the Ref of a disposed notifier throws in Riverpod 3.
    final repo = ref.read(clientsRepositoryProvider);
    final refresh = ref.read(clientsRefreshProvider.notifier);
    final logger = ref.read(loggerProvider);
    state = state.copyWith(isSaving: true);
    try {
      await repo.addClient(client);
      refresh.bump();
      return ClientSaved(client);
    } catch (e, st) {
      logger.warn('CLI-ADD addClient failed', e, st);
      return ClientSaveFailed(e);
    } finally {
      if (ref.mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// Persists an edit, then mirrors it onto the phone contact this client was
  /// saved as (no-op unless it was saved on this device; best-effort — never
  /// blocks or fails the save).
  Future<ClientSaveOutcome> updateClient(ClientRecord client) async {
    // Resolved before the first await — see addClient.
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

  /// Deletes [clientId], drops its device-local phone-contact link
  /// (best-effort, mirrors CLI-CONTACT-SYNC) and bumps the list refresh.
  Future<ClientDeleteOutcome> deleteClient(String clientId) async {
    // Resolved before the first await — see addClient.
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
