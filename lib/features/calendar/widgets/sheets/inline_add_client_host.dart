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
      return await showAddClientSheet(
        context,
        initialName: name,
        settleFocus: true,
      );
    } finally {
      if (mounted) _addingClient = false;
    }
  }
}
