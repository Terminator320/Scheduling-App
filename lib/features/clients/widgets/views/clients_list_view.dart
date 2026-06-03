import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/clients/widgets/cards/client_tile.dart';
import 'package:scheduling/features/clients/widgets/sheets/add_client_sheet.dart';
import 'package:scheduling/features/clients/widgets/sheets/client_detail_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/fade_in_item.dart';

class ClientsListView extends ConsumerStatefulWidget {
  const ClientsListView({
    required this.searchQuery,
    required this.isAdmin,
    super.key,
    this.onClientTap,
    this.selectedClientId,
  });

  final String searchQuery;
  final bool isAdmin;
  final void Function(ClientRecord client)? onClientTap;
  final String? selectedClientId;

  @override
  ConsumerState<ClientsListView> createState() => _ClientsListViewState();
}

class _ClientsListViewState extends ConsumerState<ClientsListView> {
  static const int _pageSize = 50;

  late final PagingController<int, ClientRecord> _pagingController =
      PagingController<int, ClientRecord>(
        getNextPageKey: (state) {
          final pages = state.pages;
          if (pages == null) return 1;

          if (pages.isNotEmpty && pages.last.length < _pageSize) return null;
          return (state.keys?.last ?? 0) + 1;
        },
        fetchPage: _fetchPage,
      );

  Future<List<ClientRecord>> _fetchPage(int pageKey) async {
    try {
      final items = _pagingController.value.items;
      final after = (pageKey == 1 || items == null || items.isEmpty)
          ? null
          : items.last;
      return await ref
          .read(clientsRepositoryProvider)
          .fetchClientsPage(after: after, limit: _pageSize);
    } catch (e, st) {
      ref.read(loggerProvider).warn('clients page fetch error', e, st);
      rethrow;
    }
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Future<void> _onAddClient() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AppMotion.sheetStyle,
      builder: (_) => const AddClientSheet(),
    );
  }

  Future<void> _openClient(ClientRecord client) async {
    if (widget.onClientTap != null) {
      widget.onClientTap!(client);
      return;
    }

    await SheetFocus.settleBeforeSheet();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AppMotion.sheetStyle,
      builder: (_) => ClientDetailSheet(client: client),
    );

    if (!mounted) return;
    await SheetFocus.unfocusAfterSheet();
  }

  Widget _clientTile(ClientRecord client, int index) => FadeInItem(
    key: ValueKey(client.id),
    index: index,
    child: ClientTile(
      client: client,
      selected: widget.selectedClientId == client.id,
      onOpen: () => _openClient(client),
    ),
  );

  Widget _emptyState({required String query}) {
    return AppEmptyState(
      icon: query.isEmpty ? Icons.people_outline : Icons.search_off_outlined,
      title: query.isEmpty
          ? context.l10n.clients_noClientsYet
          : '${context.l10n.clients_noClientsMatch} "$query"',
      body: query.isEmpty
          ? context.l10n.clients_tapToAddYourFirstClient
          : context.l10n.common_tryADifferentSearchTerm,
      actionLabel: query.isEmpty && widget.isAdmin
          ? context.l10n.clients_addClient
          : null,
      onAction: query.isEmpty && widget.isAdmin ? _onAddClient : null,
    );
  }

  // Non-scrolling: the first-page indicator lands inside ISP's
  // SliverFillRemaining, where a nested scrollable (ListView) would throw
  // an intrinsic-dimension error.
  Widget _skeleton() => const Padding(
    padding: EdgeInsets.all(AppSpacing.sp16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonListTile(),
        SizedBox(height: 8),
        SkeletonListTile(),
        SizedBox(height: 8),
        SkeletonListTile(),
        SizedBox(height: 8),
        SkeletonListTile(),
      ],
    ),
  );

  // Search filters the already-loaded pages (client-side), preserving the
  // app's intentional client-side search behavior on top of pagination.
  Widget _buildSearchResults(String query) {
    final loaded = _pagingController.value.items ?? const <ClientRecord>[];
    // Accent-folded text + digits-only phone matching — same rule as the
    // server-side client search.
    final q = ClientSearchPolicy.normalize(query);
    final qDigits = ClientSearchPolicy.digitsOnly(query);
    final filtered = loaded.where((c) {
      final matchesText =
          q.isNotEmpty &&
          ClientSearchPolicy.normalize(c.displayName).contains(q);
      final matchesPhone =
          qDigits.isNotEmpty &&
          ClientSearchPolicy.digitsOnly(c.phone).contains(qDigits);
      return matchesText || matchesPhone;
    }).toList();

    if (filtered.isEmpty) return _emptyState(query: query);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: filtered.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 64),
      itemBuilder: (context, index) => _clientTile(filtered[index], index),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(clientsRefreshProvider, (_, _) => _pagingController.refresh());

    final query = widget.searchQuery.trim();
    if (query.isNotEmpty) return _buildSearchResults(query);

    return RefreshIndicator(
      onRefresh: () async => _pagingController.refresh(),
      child: PagingListener<int, ClientRecord>(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) =>
            PagedListView<int, ClientRecord>.separated(
              state: state,
              fetchNextPage: fetchNextPage,
              padding: const EdgeInsets.only(bottom: 16),
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 64),
              builderDelegate: PagedChildBuilderDelegate<ClientRecord>(
                itemBuilder: (context, client, index) =>
                    _clientTile(client, index),
                firstPageProgressIndicatorBuilder: (_) => _skeleton(),
                firstPageErrorIndicatorBuilder: (_) => Center(
                  child: Text(
                    composeErrorNotice(
                      context,
                      intro: context.l10n.error_introLoadClients,
                      tag: 'CLI-LIST',
                      error:
                          state.error ?? Exception('clients page load failed'),
                    ),
                  ),
                ),
                noItemsFoundIndicatorBuilder: (_) => _emptyState(query: ''),
              ),
            ),
      ),
    );
  }
}
