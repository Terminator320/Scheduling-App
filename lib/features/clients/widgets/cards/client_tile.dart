import 'package:flutter/material.dart';

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/shared/widgets/cards/list_item_tile.dart';

class ClientTile extends StatelessWidget {
  const ClientTile({
    required this.client,
    super.key,
    this.onOpen,
    this.selected = false,
  });

  final ClientRecord client;
  final Future<void> Function()? onOpen;
  final bool selected;

  Future<void> _open(BuildContext context) async {
    if (onOpen != null) {
      await onOpen!();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClientDetailSheet(client: client),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ListItemTile's InkWell exposes button semantics and reads visible name + phone; no explicit label needed.
    return ListItemTile(
      avatarName: client.displayName,
      title: client.displayName,
      subtitle: client.phone,
      selected: selected,
      onTap: () => _open(context),
    );
  }
}
