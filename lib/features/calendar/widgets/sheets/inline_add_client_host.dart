import 'package:flutter/widgets.dart';

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';

/// Guards the inline 'add client while booking' flow against double-taps.
/// The sheet's settle step delays the modal barrier by about 80ms, so without this
/// guard a fast second tap can slip through before the barrier goes up.
mixin InlineAddClientHost<T extends StatefulWidget> on State<T> {
  bool _addingClient = false;

  Future<ClientRecord?> requestAddClient(String name) async {
    if (_addingClient) return null;
    _addingClient = true;
    try {
      // The booking form only wants the client — "Add and book a job" is
      // meaningless here, since a booking is already in progress.
      final result = await showAddClientSheet(
        context,
        initialName: name,
        settleFocus: true,
      );
      return result?.client;
    } finally {
      if (mounted) _addingClient = false;
    }
  }
}
