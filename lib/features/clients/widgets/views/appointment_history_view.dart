import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/clients/application/appointment_history_providers.dart';
import 'package:scheduling/features/clients/domain/history_grouping.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/clients/widgets/lists/history_date_rail.dart';
import 'package:scheduling/features/clients/widgets/sections/history_filter_bar.dart';
import 'package:scheduling/features/clients/widgets/sections/history_month_bar.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';

/// A pre-normalized searchable projection, built once per page load so filtering on
/// every keystroke stays cheap.
typedef _HistorySearchEntry = ({
  AppointmentRecord appointment,
  String clientText,
  List<String> employeeTexts,
  String phoneDigits,
});

/// Paginated history list, newest first. Filters and search both operate over the
/// pages already loaded on the client, not a fresh server query.
class AppointmentHistoryView extends ConsumerStatefulWidget {
  const AppointmentHistoryView({
    required this.searchQuery,
    super.key,
    this.isAdmin = false,
    this.filterTourWrap,
    this.firstRowTourWrap,
    this.onFirstPageSettled,
  });

  final String searchQuery;

  /// The caller's resolved role, passed straight to `showEventDetails` as
  /// `showActions`. Defaults CLOSED, like every other appointment surface —
  /// a `true` default silently offers employees actions the rules reject with
  /// an opaque `permission-denied`.
  ///
  /// History holds only `done` and `cancelled` jobs, so for an admin this
  /// opens exactly one affordance per row: the action bar's Edit button on a
  /// finished one, the edit chip on a cancelled one. Mark-as-done and Cancel
  /// both hide themselves on a terminal job.
  final bool isAdmin;

  /// Wraps the filter bar as its feature-tour step. Null when the host has
  /// no tour for it.
  final Widget Function(Widget child)? filterTourWrap;

  /// Wraps the FIRST row only, as that row's feature-tour step. One row, not
  /// every row — the step's GlobalKey has to stay unique.
  final Widget Function(Widget child)? firstRowTourWrap;

  /// Fires after the first page has settled and been laid out — success or
  /// failure, since either way the skeleton is gone and no further row will
  /// appear on its own. A tour host gates `FeatureTourHost.ready` on this:
  /// the filter bar only renders once a page has loaded and the first row
  /// doesn't exist before then, so a tour started earlier drops BOTH steps and
  /// marks the WHOLE scope seen.
  final VoidCallback? onFirstPageSettled;

  @override
  ConsumerState<AppointmentHistoryView> createState() =>
      _AppointmentHistoryViewState();
}

class _AppointmentHistoryViewState
    extends ConsumerState<AppointmentHistoryView> {
  static const int _pageSize = 25;

  /// How close to the end of the loaded rows a build has to reach before the
  /// next page is requested. The list drives its own pagination now that it
  /// builds slivers by month, so this is the threshold `PagedListView` used to
  /// own.
  static const int _prefetchThreshold = 3;

  // Debounce before running a history search, same as the clients list. The
  // loaded-page filter covers the gap in the meantime so it still feels instant.
  final _searchDebounce = Debouncer(const Duration(milliseconds: 250));

  int? _year;
  String? _employeeId;
  HistoryStatusFilter? _status;

  String _committedQuery = '';

  // Filter options and the search index are memoized — they only get recomputed when
  // a new page arrives, not on every filter setState.
  List<List<AppointmentRecord>>? _filterOptionsPages;
  List<int> _cachedYears = const [];
  List<HistoryEmployeeOption> _cachedEmployees = const [];
  List<_HistorySearchEntry> _searchIndex = const [];

  late final PagingController<int, AppointmentRecord> _pagingController =
      PagingController<int, AppointmentRecord>(
        getNextPageKey: (state) {
          final pages = state.pages;
          if (pages == null) return 1;
          if (pages.isNotEmpty && pages.last.length < _pageSize) return null;
          return (state.keys?.last ?? 0) + 1;
        },
        fetchPage: _fetchPage,
      );

  @override
  void initState() {
    super.initState();
    // Load first page upfront so search/filter has data when view opens directly into filtered state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pagingController.fetchNextPage();
    });
  }

  Future<List<AppointmentRecord>> _fetchPage(int pageKey) async {
    try {
      final items = _pagingController.value.items;
      final after = (pageKey == 1 || items == null || items.isEmpty)
          ? null
          : items.last;
      return await ref
          .read(historyPagerProvider)
          .fetchPage(after: after, limit: _pageSize);
    } catch (e, st) {
      ref
          .read(loggerProvider)
          .warn('HIST-LOAD history page fetch error', e, st);
      rethrow;
    } finally {
      if (pageKey == 1) _notifyFirstPageSettled();
    }
  }

  /// Post-frame, so the filter bar and first row the tour targets have
  /// actually been laid out by the time the host asks showcase about them.
  void _notifyFirstPageSettled() {
    final notify = widget.onFirstPageSettled;
    if (notify == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify();
    });
  }

  @override
  void didUpdateWidget(covariant AppointmentHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery.trim() == oldWidget.searchQuery.trim()) return;
    _scheduleSearch();
  }

  // Restart the debounce on every query change. Clearing the query, though, commits
  // instantly instead of waiting.
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

  void _clearFilters() => setState(() {
    _year = null;
    _employeeId = null;
    _status = null;
  });

  // Filter options are derived from the loaded pages so a selection never
  // makes its own chip's other options disappear.
  List<int> _yearsOf(List<AppointmentRecord> appointments) {
    final years = <int>{for (final a in appointments) a.startTime.year};
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<HistoryEmployeeOption> _employeesOf(
    List<AppointmentRecord> appointments,
  ) {
    final names = <String, String>{};
    for (final a in appointments) {
      for (var i = 0; i < a.employeeIds.length; i++) {
        final id = a.employeeIds[i];
        if (id.isEmpty) continue;
        final name = assigneeNameAt(a.employeeNames, i) ?? '';
        final existing = names[id];
        if (existing == null || (existing.isEmpty && name.isNotEmpty)) {
          names[id] = name;
        }
      }
    }
    final options = [
      for (final e in names.entries)
        (id: e.key, name: e.value.isEmpty ? e.key : e.value),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return options;
  }

  bool get _hasChipFilter =>
      _year != null || _employeeId != null || _status != null;

  bool get _hasActiveFilter =>
      widget.searchQuery.trim().isNotEmpty || _hasChipFilter;

  // Applies only the chip filters, no text search. Used on top of either the
  // loaded pages or the server-backed search results.
  List<AppointmentRecord> _applyChips(List<AppointmentRecord> appointments) =>
      appointments.where(_matchesChips).toList();

  bool _matchesChips(AppointmentRecord a) {
    if (_year != null && a.startTime.year != _year) return false;
    if (_employeeId != null && !a.employeeIds.contains(_employeeId)) {
      return false;
    }
    if (_status != null && !_status!.matches(a)) return false;
    return true;
  }

  // Chip + text filtering over the loaded pages, via the memoized
  // [_searchIndex] so each keystroke only normalizes the (short) query — the
  // per-row normalization already happened when the page arrived.
  List<AppointmentRecord> _filterLoaded() {
    final hasQuery = widget.searchQuery.trim().isNotEmpty;
    // Accent-folded text + digits-only phone matching — same rule as the
    // clients list, so a client's phone number finds their appointments.
    final qText = ClientSearchPolicy.normalize(widget.searchQuery);
    final qDigits = ClientSearchPolicy.digitsOnly(widget.searchQuery);
    return [
      for (final entry in _searchIndex)
        if (_matchesChips(entry.appointment) &&
            (!hasQuery || _matchesQuery(entry, qText, qDigits)))
          entry.appointment,
    ];
  }

  bool _matchesQuery(_HistorySearchEntry entry, String qText, String qDigits) {
    if (qText.isEmpty && qDigits.isEmpty) return false;
    final matchesClient = qText.isNotEmpty && entry.clientText.contains(qText);
    final matchesEmployee =
        qText.isNotEmpty && entry.employeeTexts.any((e) => e.contains(qText));
    final matchesPhone =
        qDigits.isNotEmpty && entry.phoneDigits.contains(qDigits);
    return matchesClient || matchesEmployee || matchesPhone;
  }

  /// The filter row renders as soon as any history has loaded — the two status
  /// chips are always offerable, since `done` and `cancelled` are what History
  /// holds by definition. The year and crew chips still hide themselves when
  /// there is nothing to choose between.
  Widget _filterBar(List<int> years, List<HistoryEmployeeOption> employees) {
    final bar = Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sp8,
        bottom: AppSpacing.sp4,
      ),
      child: HistoryFilterBar(
        years: years,
        selectedYear: _year,
        onYearChanged: (v) => setState(() => _year = v),
        employees: employees,
        selectedEmployeeId: _employeeId,
        onEmployeeChanged: (v) => setState(() => _employeeId = v),
        selectedStatus: _status,
        onStatusChanged: (v) => setState(() => _status = v),
      ),
    );
    return widget.filterTourWrap?.call(bar) ?? bar;
  }

  @override
  Widget build(BuildContext context) {
    final colorMap = ref.watch(employeeColorMapProvider);
    // The rail speaks the year on an older search hit, so "this year" has to
    // survive an app left open across New Year — same reason the calendar's
    // today circle reads this provider rather than DateTime.now().
    final currentYear = ref.watch(currentDayProvider).year;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: PagingListener<int, AppointmentRecord>(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) {
          final loaded = state.items ?? const <AppointmentRecord>[];
          // PagingState.items rebuilds a fresh list each access, so memoize on
          // the underlying pages identity, which only changes on a new page.
          if (!identical(state.pages, _filterOptionsPages)) {
            _filterOptionsPages = state.pages;
            _cachedYears = _yearsOf(loaded);
            _cachedEmployees = _employeesOf(loaded);
            _searchIndex = [
              for (final a in loaded)
                (
                  appointment: a,
                  clientText: ClientSearchPolicy.normalize(a.clientName),
                  employeeTexts: [
                    for (final e in a.employeeNames)
                      ClientSearchPolicy.normalize(e),
                  ],
                  phoneDigits: ClientSearchPolicy.digitsOnly(a.clientPhone),
                ),
            ];
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loaded.isNotEmpty) _filterBar(_cachedYears, _cachedEmployees),
              Expanded(
                child: _hasActiveFilter
                    ? _buildFiltered(colorMap, currentYear)
                    : _buildPaged(
                        state,
                        loaded,
                        fetchNextPage,
                        colorMap,
                        currentYear,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaged(
    PagingState<int, AppointmentRecord> state,
    // Hoisted out of the itemBuilder on purpose: PagingState.items is a
    // computed getter that re-flattens every loaded page on each access, so
    // reading it per row copied the whole list once per built row — O(N) per
    // row, growing with scroll depth. Same value, resolved once.
    List<AppointmentRecord> loaded,
    void Function() fetchNextPage,
    Map<String, Color> colorMap,
    int currentYear,
  ) {
    if (loaded.isEmpty) {
      if (state.status == PagingStatus.loadingFirstPage) {
        _requestFirstPage(state, fetchNextPage);
      }
      // Deliberately NOT wrapped in the RefreshIndicator: `AppEmptyState`
      // carries its own `SingleChildScrollView`, so putting one of ours around
      // it would leave two controllerless primary scrollables under this
      // route's `PrimaryScrollScope` — which is what makes the app-wide
      // Scrollbar throw. The Retry button covers the failed case; the empty
      // one has nothing to re-fetch.
      return switch (state.status) {
        PagingStatus.loadingFirstPage => _skeleton(),
        PagingStatus.firstPageError => _errorState(
          state.error ?? Exception('history page load failed'),
          onRetry: _pagingController.refresh,
        ),
        _ => AppEmptyState(
          icon: Icons.history_outlined,
          title: context.l10n.common_noAppointmentsFound,
          body: context.l10n.common_tapToScheduleAnAppointment,
        ),
      };
    }

    return RefreshIndicator.adaptive(
      onRefresh: () async => _pagingController.refresh(),
      child: _countedList(
        rows: loaded,
        colorMap: colorMap,
        currentYear: currentYear,
        inSearch: false,
        footer: _pagingFooter(state, fetchNextPage),
        onRowBuilt: (index) =>
            _maybeFetchNext(state, fetchNextPage, index, loaded.length),
      ),
    );
  }

  /// Requests the first page whenever the state is back at square one.
  ///
  /// `PagingController.refresh()` only RESETS the state — it does not fetch —
  /// so both pull-to-refresh and the first-page Retry rely on someone noticing
  /// the reset and asking again. `PagedListView` used to be that someone; this
  /// list builds its own slivers, so it has to be. Without it a refresh leaves
  /// the skeleton shimmering forever with no request in flight.
  void _requestFirstPage(
    PagingState<int, AppointmentRecord> state,
    void Function() fetchNextPage,
  ) {
    if (state.isLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fetchNextPage();
    });
  }

  /// Requests the next page once a build reaches within [_prefetchThreshold]
  /// rows of the end.
  ///
  /// Always post-frame: `PagingController.fetchNextPage` assigns its own value
  /// synchronously, so calling it from an item builder would mutate a listenable
  /// mid-build. It is a mutex besides, so a repeat while one is in flight is a
  /// no-op — but a failed page is left alone, or the list would spin on a retry
  /// nobody asked for.
  void _maybeFetchNext(
    PagingState<int, AppointmentRecord> state,
    void Function() fetchNextPage,
    int index,
    int total,
  ) {
    if (index < total - _prefetchThreshold) return;
    if (!state.hasNextPage || state.isLoading || state.error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fetchNextPage();
    });
  }

  /// The tail of the paged list: a spinner while the next page is in flight, a
  /// tap-to-retry row when one failed, and nothing at all once the list is
  /// complete.
  Widget _pagingFooter(
    PagingState<int, AppointmentRecord> state,
    void Function() fetchNextPage,
  ) {
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp16),
        child: Center(
          child: TextButton(
            onPressed: fetchNextPage,
            child: Text(context.l10n.common_retry),
          ),
        ),
      );
    }
    if (!state.isLoading) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sp16),
      // Through the one adaptive seam, not `.adaptive()`: that branches on
      // `defaultTargetPlatform`, which a test forcing the look via
      // `ThemeData(platform:)` cannot reach. Sized to keep the old footprint.
      child: Center(child: AdaptiveProgressIndicator(size: 36, strokeWidth: 4)),
    );
  }

  Widget _buildFiltered(Map<String, Color> colorMap, int currentYear) {
    final query = widget.searchQuery.trim();

    Widget list(List<AppointmentRecord> rows, {required bool inSearch}) {
      if (rows.isEmpty) return _buildEmptyState(context);
      return _countedList(
        rows: rows,
        colorMap: colorMap,
        currentYear: currentYear,
        inSearch: inSearch,
      );
    }

    // No text query — chip filters alone operate over the loaded pages, which
    // stay a contiguous run of days and so keep their month bars.
    if (query.isEmpty) {
      return list(_filterLoaded(), inSearch: false);
    }

    // The local page filter fills the gap until the debounced server search settles.
    // It's computed lazily, so the settled `data` branch — which renders the server
    // results — doesn't end up re-filtering on every rebuild.
    Widget localOr(Widget Function() onEmpty) {
      final local = _filterLoaded();
      return local.isEmpty ? onEmpty() : list(local, inSearch: true);
    }

    if (_committedQuery != query) {
      return localOr(_skeleton);
    }

    return ref
        .watch(historySearchProvider(query))
        .when(
          data: (results) => list(_applyChips(results), inSearch: true),
          loading: () => localOr(_skeleton),
          // A failed search shouldn't read as "no history" — surface an error
          // when the local fallback is also empty, not the empty state.
          error: (e, _) => localOr(() => _searchError(e, query)),
        );
  }

  // Retry re-runs the failed search by invalidating its provider instance;
  // this rebuild is already watching it, so it refetches immediately.
  Widget _searchError(Object error, String query) => _errorState(
    error,
    onRetry: () => ref.invalidate(historySearchProvider(query)),
  );

  Widget _errorState(Object error, {required VoidCallback onRetry}) =>
      AppEmptyState(
        icon: Icons.error_outline,
        title: context.l10n.error_somethingWentWrong,
        body: composeErrorNotice(
          context,
          intro: context.l10n.error_introLoadHistory,
          error: error,
        ),
        actionLabel: context.l10n.common_retry,
        onAction: onRetry,
      );

  /// The count line and the rows it describes.
  ///
  /// The count is the ONE count on this screen. Per-month counts are
  /// deliberately absent: History is paginated, so an early month could only
  /// ever report what had loaded, which is a figure that climbs while you read
  /// it.
  Widget _countedList({
    required List<AppointmentRecord> rows,
    required Map<String, Color> colorMap,
    required int currentYear,
    required bool inSearch,
    Widget? footer,
    void Function(int index)? onRowBuilt,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _HistoryCountLine(tally: tallyOf(rows), inSearch: inSearch),
      Expanded(
        child: _historyList(
          rows: rows,
          colorMap: colorMap,
          currentYear: currentYear,
          inSearch: inSearch,
          footer: footer,
          onRowBuilt: onRowBuilt,
        ),
      ),
    ],
  );

  /// The rows themselves — month-barred, or flat in search.
  ///
  /// Search spans every appointment rather than the month in view, so its hits
  /// are not a contiguous run of days and month bars over scattered results
  /// would be noise. The rail picks up the month instead.
  Widget _historyList({
    required List<AppointmentRecord> rows,
    required Map<String, Color> colorMap,
    required int currentYear,
    required bool inSearch,
    Widget? footer,
    void Function(int index)? onRowBuilt,
  }) {
    Widget item(int index) => _historyItem(
      rows,
      index,
      colorMap,
      inSearch: inSearch,
      currentYear: currentYear,
      onRowBuilt: onRowBuilt,
    );

    final monthFormat = monthYearFormatFor(
      Localizations.localeOf(context).toString(),
    );
    final extent = HistoryMonthBar.extentFor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
      child: CustomScrollView(
        slivers: [
          if (inSearch)
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) => item(index),
            )
          else
            for (final section in monthSectionsOf(rows))
              // The group is what makes the bar STICKY rather than STACKING: a
              // pinned header is bounded by its group's scroll extent, so July's
              // bar pushes August's out on the way past instead of parking a
              // second bar under it. A year of history would otherwise pile
              // twelve bars across the top of the screen.
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: HistoryMonthBar(
                      label: monthFormat.format(section.month),
                      extent: extent,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: section.length,
                    itemBuilder: (context, index) =>
                        item(section.start + index),
                  ),
                ],
              ),
          // The paged list's spinner or retry row, and — with or without one —
          // the gap that keeps the last card off the bottom edge.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sp12),
              child: footer ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// Every row goes through here, so the first-row tour wrap and the pager's
  /// prefetch both key off ONE global index rather than a per-section one.
  Widget _historyItem(
    List<AppointmentRecord> rows,
    int index,
    Map<String, Color> colorMap, {
    required bool inSearch,
    required int currentYear,
    void Function(int index)? onRowBuilt,
  }) {
    onRowBuilt?.call(index);
    final row = _historyRow(
      rows,
      index,
      colorMap,
      inSearch: inSearch,
      currentYear: currentYear,
    );
    final wrap = widget.firstRowTourWrap;
    return index == 0 && wrap != null ? wrap(row) : row;
  }

  Widget _historyRow(
    List<AppointmentRecord> rows,
    int index,
    Map<String, Color> colorMap, {
    required bool inSearch,
    required int currentYear,
  }) {
    final app = rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Drops the rail's first line onto the card's title line rather
            // than its top border.
            padding: const EdgeInsets.only(top: AppSpacing.sp16),
            child: HistoryDateRail(
              day: DateUtils.dateOnly(app.startTime),
              showDate: startsDay(rows, index),
              inSearch: inSearch,
              currentYear: currentYear,
            ),
          ),
          Expanded(
            child: AppointmentCard(
              appointment: app,
              // No live name map here — crewFor falls back to the record's
              // denormalized employeeNames.
              crew: crewFor(app, colorMap: colorMap),
              // Dims a cancelled visit to 0.6 and strikes its title through.
              // History keeps the plain full-height card otherwise: the
              // agenda's collapsed green treatment exists to sink closed work
              // out of the way of what's left today, and here everything is
              // closed.
              dimWhenCancelled: true,
              // Carries the caller's role rather than a hardcoded false: an
              // admin needs to reach a finished job's Edit button from here,
              // which is where finished jobs actually live.
              onTap: () =>
                  showEventDetails(context, app, showActions: widget.isAdmin),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton() =>
      const SkeletonList(padding: EdgeInsets.all(AppSpacing.sp12));

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    final query = widget.searchQuery.trim();

    if (query.isNotEmpty && !_hasChipFilter) {
      return AppEmptyState(
        icon: Icons.search_off_outlined,
        title: '${l10n.clients_noAppointmentsMatch} "$query"',
        body: l10n.common_tryADifferentSearchTerm,
      );
    }
    return AppEmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: l10n.clients_noAppointmentsMatchFilters,
      body: l10n.common_tryADifferentSearchTerm,
      actionLabel: _hasChipFilter ? l10n.clients_clearFilters : null,
      onAction: _hasChipFilter ? _clearFilters : null,
    );
  }
}

/// `18 JOBS · 2 CANCELLED` — the one count on the screen.
///
/// The cancelled clause is a SUBSET of the total, not an addition, the same
/// shape as the calendar agenda's `4 JOBS · 1 DONE`. Search says `RESULTS`
/// instead of `JOBS` and keeps the clause: dropping it on one state and not the
/// other would read as a different metric.
class _HistoryCountLine extends StatelessWidget {
  const _HistoryCountLine({required this.tally, required this.inSearch});

  final HistoryTally tally;
  final bool inSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final head = inSearch
        ? l10n.clients_historyResultsCount(tally.total)
        : l10n.clients_historyJobsCount(tally.total);
    final label = tally.cancelled == 0
        ? head
        : '$head · ${l10n.clients_historyCancelledCount(tally.cancelled)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp12,
        AppSpacing.sp8,
        AppSpacing.sp12,
        AppSpacing.sp8,
      ),
      child: Text(label, style: Theme.of(context).monoType.label),
    );
  }
}
