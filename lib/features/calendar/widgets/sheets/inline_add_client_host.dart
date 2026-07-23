import 'package:flutter/widgets.dart';

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';

/// Shared double-tap guard for inline 'add client while booking' (sheet settle delays the barrier ~80ms).
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
