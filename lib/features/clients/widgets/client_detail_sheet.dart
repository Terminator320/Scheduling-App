import 'package:flutter/material.dart';

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/client_detail_view.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class ClientDetailSheet extends StatelessWidget {
  const ClientDetailSheet({required this.client, super.key});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return ClientDetailView(
          client: client,
          scrollController: scrollController,
          showHandle: true,
        );
      },
    );
  }
}
