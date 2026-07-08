import 'package:flutter/widgets.dart';

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';

/// Shared double-tap guard for the inline "add a client while booking"
/// affordance used by the two appointment hosts (the add sheet and the edit
/// body). The sheet-from-search settle delays the modal barrier ~80ms, leaving
/// the trigger tappable, so an unguarded second tap would stack a second sheet
/// (duplicate client). Each host mixes this in and calls [requestAddClient] as
/// the `onRequestAddClient` callback.
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
