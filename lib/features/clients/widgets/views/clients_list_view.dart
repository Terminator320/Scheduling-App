import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
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
    this.selectedType,
    this.onClientTap,
    this.selectedClientId,
  });

  final String searchQuery;
  final bool isAdmin;

  /// When set, the list shows only clients of this type, read as one bounded
  /// query rather than filtered out of the paginated list.
  final ClientType? selectedType;
  final void Function(ClientRecord client)? onClientTap;
  final String? selectedClientId;

  @override
  ConsumerState<ClientsListView> createState() => _ClientsListViewState();
}

class _ClientsListViewState extends ConsumerState<ClientsListView> {
  static const int _pageSize = 50;
  // Debounce before the server search, so we don't fire a read on every keystroke —
  // the local filter covers the gap in the meantime so it still feels immediate.
  final _searchDebounce = Debouncer(const Duration(milliseconds: 250));
  String _committedQuery = '';

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
      ref.read(loggerProvider).warn('CLI-LIST clients page fetch error', e, st);
      rethrow;
    }
  }

  @override
  void didUpdateWidget(covariant ClientsListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery.trim() == oldWidget.searchQuery.trim()) return;
    _scheduleSearch();
  }

  // The debounce restarts on every query change, but clearing the query commits
  // instantly, so returning to the paged list has zero lag.
  void _scheduleSearch() {
    final next = widget.searchQuery.trim();
    if (next.isEmpty) {
      _searchDebounce.cancel();
      if (_committedQuery.isNotEmpty) setState(() => _committedQuery = '');
      return;
    }
    _searchDebounce.run(() {
      if (mounted && next != _committedQuery) {
        setState(() => _committedQuery = next);
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _pagingController.dispose();
    super.dispose();
  }

  Future<void> _onAddClient() async {
    final result = await showAddClientSheet(context);
    if (result == null || result.next != AddClientNext.bookJob) return;
    if (!mounted) return;
    // Sequential, never stacked — the add-client sheet has already popped.
    await showAddEventPopup(context, initialClient: result.client);
  }

  Future<void> _openClient(ClientRecord client) async {
    if (widget.onClientTap != null) {
      widget.onClientTap!(client);
      return;
    }

    await showClientDetailSheet(context, client);
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

  // This can't scroll itself — the first-page indicator lands inside ISP's
  // SliverFillRemaining, and a nested scrollable (ListView) there would throw an
  // intrinsic-dimension error.
  Widget _skeleton() => const Padding(
    padding: EdgeInsets.all(AppSpacing.sp16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonListTile(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonListTile(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonListTile(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonListTile(),
      ],
    ),
  );

  // Pre-normalized search index over the loaded pages, memoized on the pages
  // identity so normalization reruns only when a page loads, not on every
  // keystroke (mirrors _employeeSearchIndexProvider and the history view's
  // _filterOptionsPages memo).
  List<List<ClientRecord>>? _searchIndexPages;
  List<ClientSearchEntry> _searchIndex = const [];

  List<ClientSearchEntry> _loadedSearchIndex() {
    final state = _pagingController.value;
    if (!identical(state.pages, _searchIndexPages)) {
      _searchIndexPages = state.pages;
      _searchIndex = [
        for (final client in state.items ?? const <ClientRecord>[])
          ClientSearchPolicy.index(client),
      ];
    }
    return _searchIndex;
  }

  // Instant fallback over the already-loaded pages while the comprehensive
  // server search resolves, matching the full field set via the shared policy.
  List<ClientRecord> _localFilter(String query) {
    final q = ClientSearchPolicy.normalize(query);
    final qDigits = ClientSearchPolicy.digitsOnly(query);
    if (q.isEmpty && qDigits.isEmpty) return const [];
    return [
      for (final entry in _loadedSearchIndex())
        if (ClientSearchPolicy.entryMatches(
          entry,
          queryText: q,
          queryDigits: qDigits,
        ))
          entry.client,
    ];
  }

  // The full search runs on the debounced, committed query across all fields and
  // pages. The instant local filter fills the gap until that settles.
  Widget _buildSearchResults(String query) {
    final local = _localFilter(query);

    if (_committedQuery != query) {
      // Still typing — show instant local results (skeleton if none yet).
      return local.isEmpty ? _skeleton() : _resultsList(local);
    }

    return ref
        .watch(clientSearchProvider(query))
        .when(
          data: (results) => results.isEmpty
              ? _emptyState(query: query)
              : _resultsList(results),
          loading: () => local.isEmpty ? _skeleton() : _resultsList(local),
          // A failed search must not look like "no such client" — show an
          // error when the instant local fallback is also empty, not the empty state.
          error: (e, _) =>
              local.isEmpty ? _searchError(e, query) : _resultsList(local),
        );
  }

  // Pre-normalized index over the type-filtered list, memoized on the list
  // identity for the same reason _loadedSearchIndex is — this view rebuilds on
  // every keystroke, and re-indexing the whole filtered slice each time is the
  // expensive half of matching.
  List<ClientRecord>? _typeIndexSource;
  List<ClientSearchEntry> _typeIndex = const [];

  List<ClientSearchEntry> _typeSearchIndex(List<ClientRecord> all) {
    if (!identical(all, _typeIndexSource)) {
      _typeIndexSource = all;
      _typeIndex = [for (final client in all) ClientSearchPolicy.index(client)];
    }
    return _typeIndex;
  }

  // A type filter is a bounded, already-in-memory list, so searching within it
  // is the shared local matcher rather than a second server query.
  Widget _buildTypeResults(ClientType type) {
    final query = widget.searchQuery.trim();
    return ref
        .watch(clientsByTypeProvider(type))
        .when(
          data: (all) {
            final q = ClientSearchPolicy.normalize(query);
            final qDigits = ClientSearchPolicy.digitsOnly(query);
            final items = query.isEmpty
                ? all
                : [
                    for (final entry in _typeSearchIndex(all))
                      if (ClientSearchPolicy.entryMatches(
                        entry,
                        queryText: q,
                        queryDigits: qDigits,
                      ))
                        entry.client,
                  ];
            return items.isEmpty
                ? _typeEmptyState(type: type, query: query)
                : _resultsList(items);
          },
          loading: _skeleton,
          error: (e, _) => _errorState(
            e,
            onRetry: () => ref.invalidate(clientsByTypeProvider(type)),
          ),
        );
  }

  Widget _typeEmptyState({required ClientType type, required String query}) =>
      AppEmptyState(
        icon: Icons.filter_list_off_outlined,
        title: query.isEmpty
            ? context.l10n.clients_noClientsOfType(
                clientTypeLabel(context.l10n, type),
              )
            : '${context.l10n.clients_noClientsMatch} "$query"',
        body: query.isEmpty
            ? context.l10n.clients_typeFilterHint
            : context.l10n.common_tryADifferentSearchTerm,
      );

  // Retry re-runs the failed search by invalidating its provider instance;
  // this rebuild is already watching it, so it refetches immediately.
  Widget _searchError(Object error, String query) => _errorState(
    error,
    onRetry: () => ref.invalidate(clientSearchProvider(query)),
  );

  Widget _errorState(Object error, {required VoidCallback onRetry}) =>
      AppEmptyState(
        icon: Icons.error_outline,
        title: context.l10n.error_somethingWentWrong,
        body: composeErrorNotice(
          context,
          intro: context.l10n.error_introLoadClients,
          tag: 'CLI-LIST',
          error: error,
        ),
        actionLabel: context.l10n.common_retry,
        onAction: onRetry,
      );

  Widget _resultsList(List<ClientRecord> items) => ListView.separated(
    padding: const EdgeInsets.only(bottom: AppSpacing.sp16),
    itemCount: items.length,
    separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
    itemBuilder: (context, index) => _clientTile(items[index], index),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(clientsRefreshProvider, (_, _) => _pagingController.refresh());

    final type = widget.selectedType;
    if (type != null) return _buildTypeResults(type);

    final query = widget.searchQuery.trim();
    if (query.isNotEmpty) return _buildSearchResults(query);

    return RefreshIndicator.adaptive(
      onRefresh: () async => _pagingController.refresh(),
      child: PagingListener<int, ClientRecord>(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) =>
            PagedListView<int, ClientRecord>.separated(
              state: state,
              fetchNextPage: fetchNextPage,
              padding: const EdgeInsets.only(bottom: AppSpacing.sp16),
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 64),
              builderDelegate: PagedChildBuilderDelegate<ClientRecord>(
                itemBuilder: (context, client, index) =>
                    _clientTile(client, index),
                firstPageProgressIndicatorBuilder: (_) => _skeleton(),
                firstPageErrorIndicatorBuilder: (_) => _errorState(
                  state.error ?? Exception('clients page load failed'),
                  onRetry: _pagingController.refresh,
                ),
                noItemsFoundIndicatorBuilder: (_) => _emptyState(query: ''),
              ),
            ),
      ),
    );
  }
}
