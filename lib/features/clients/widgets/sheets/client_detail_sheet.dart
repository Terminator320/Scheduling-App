import 'package:flutter/material.dart';

import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/views/client_detail_view.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Opens read-only client detail sheet with settle/unfocus sequence; shared by list and master-detail.
Future<void> showClientDetailSheet(
  BuildContext context,
  ClientRecord client,
) async {
  await SheetFocus.settleBeforeSheet();
  if (!context.mounted) return;

  await showAppBottomSheet<void>(
    context,
    builder: (_) => ClientDetailSheet(client: client),
  );

  if (!context.mounted) return;
  await SheetFocus.unfocusAfterSheet();
}

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
