import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/client_detail_sheet.dart';
import 'package:scheduling/features/clients/widgets/client_tile.dart';
import 'package:scheduling/shared/widgets/app_empty_state.dart';
import 'package:scheduling/shared/widgets/fade_in_item.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';

/// Body of the clients list mode: skeleton → list + search → empty state.
/// Watches `clientsStreamProvider` so the same Firestore listener serves
/// every screen that watches it (perf #1, dedup listeners).
class ClientsListView extends ConsumerStatefulWidget {
  const ClientsListView({
    required this.searchQuery,
    required this.isAdmin,
    super.key,
  });

  final String searchQuery;
  final bool isAdmin;

  @override
  ConsumerState<ClientsListView> createState() => _ClientsListViewState();
}

class _ClientsListViewState extends ConsumerState<ClientsListView> {
  final ScrollController _scrollController = ScrollController();
  int _displayLimit = 50;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      setState(() => _displayLimit += 50);
    }
  }

  Future<void> _onAddClient() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
      builder: (_) => const AddClientSheet(),
    );
  }

  Future<void> _openClient(ClientRecord client) async {
    await SheetFocus.settleBeforeSheet();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
      builder: (_) => ClientDetailSheet(client: client),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsStreamProvider);

    return clientsAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: const [
          SkeletonListTile(),
          SizedBox(height: 8),
          SkeletonListTile(),
          SizedBox(height: 8),
          SkeletonListTile(),
          SizedBox(height: 8),
          SkeletonListTile(),
        ],
      ),
      error: (err, st) {
        ref.read(loggerProvider).warn('clients stream error', err, st);
        return Center(child: Text(context.l10n.somethingWentWrong));
      },
      data: (_) {
        // ref.watch the family provider so the filter recomputes when the
        // underlying list or query changes — single source of truth.
        final filtered = ref.watch(filteredClientsProvider(widget.searchQuery));
        final query = widget.searchQuery.trim();

        final displayed = filtered.length > _displayLimit
            ? filtered.sublist(0, _displayLimit)
            : filtered;

        if (displayed.isEmpty) {
          return AppEmptyState(
            icon: query.isEmpty
                ? Icons.people_outline
                : Icons.search_off_outlined,
            title: query.isEmpty
                ? context.l10n.noClientsYet
                : '${context.l10n.noClientsMatch} "$query"',
            body: query.isEmpty
                ? context.l10n.tapToAddYourFirstClient
                : context.l10n.tryADifferentSearchTerm,
            actionLabel: query.isEmpty && widget.isAdmin
                ? context.l10n.addClient
                : null,
            onAction: query.isEmpty && widget.isAdmin ? _onAddClient : null,
          );
        }

        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: displayed.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, indent: 64),
          itemBuilder: (context, index) => FadeInItem(
            key: ValueKey(displayed[index].id),
            index: index,
            child: ClientTile(
              client: displayed[index],
              onOpen: () => _openClient(displayed[index]),
            ),
          ),
        );
      },
    );
  }
}
