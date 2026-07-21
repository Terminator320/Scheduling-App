import 'package:flutter/material.dart';

import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/views/client_detail_view.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Opens the read-only [ClientDetailSheet] for [client], with the
/// sheet-from-search settle/unfocus sequence around it — settle the keyboard
/// before the sheet slides in, double-unfocus after it closes. Shared by the
/// clients list and the master-detail single-pane tap path so both stay in
/// lockstep.
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
