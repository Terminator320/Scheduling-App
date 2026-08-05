import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/clients/application/appointment_history_providers.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/clients/widgets/sections/history_filter_bar.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

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
  /// opens exactly one affordance per row: "Edit completed job" on a finished
  /// one, the edit chip on a cancelled one. Mark-as-done and Cancel both
  /// hide themselves on a terminal job.
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
  /// the filter bar only renders once a page has supplied years/employees and
  /// the first row doesn't exist before then, so a tour started earlier drops
  /// BOTH steps and marks the WHOLE scope seen.
  final VoidCallback? onFirstPageSettled;

  @override
  ConsumerState<AppointmentHistoryView> createState() =>
      _AppointmentHistoryViewState();
}

class _AppointmentHistoryViewState
    extends ConsumerState<AppointmentHistoryView> {
  static const int _pageSize = 25;
  // Debounce before running a history search, same as the clients list. The
  // loaded-page filter covers the gap in the meantime so it still feels instant.
  final _searchDebounce = Debouncer(const Duration(milliseconds: 250));

  int? _year;
  String? _employeeId;

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
        final name = i < a.employeeNames.length ? a.employeeNames[i] : '';
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

  bool get _hasActiveFilter =>
      widget.searchQuery.trim().isNotEmpty ||
      _year != null ||
      _employeeId != null;

  // Applies only the year/employee chip filters, no text search. Used on top of either
  // the loaded pages or the server-backed search results.
  List<AppointmentRecord> _applyChips(List<AppointmentRecord> appointments) =>
      appointments.where(_matchesChips).toList();

  bool _matchesChips(AppointmentRecord a) {
    if (_year != null && a.startTime.year != _year) return false;
    if (_employeeId != null && !a.employeeIds.contains(_employeeId)) {
      return false;
    }
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

  // Builds one history entry along with the year/day headers that open its group —
  // whether a header shows is worked out by comparing against the previous item in
  // [items]. Shared by the paged and filtered list paths so grouping looks identical
  // either way.
  /// The filter row is only rendered when there is something to filter by, so
  /// on a thin history the tour step self-skips via isTargetRendered.
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
        allYearsLabel: context.l10n.clients_allYears,
        allStaffLabel: context.l10n.clients_allStaff,
      ),
    );
    return widget.filterTourWrap?.call(bar) ?? bar;
  }

  /// Both list paths (paged and filtered) build rows through here, so the
  /// first-row tour wrap lives here rather than at each itemBuilder.
  Widget _historyItem(
    List<AppointmentRecord> items,
    int index,
    Map<String, Color> colorMap,
  ) {
    final row = _historyRow(items, index, colorMap);
    final wrap = widget.firstRowTourWrap;
    return index == 0 && wrap != null ? wrap(row) : row;
  }

  Widget _historyRow(
    List<AppointmentRecord> items,
    int index,
    Map<String, Color> colorMap,
  ) {
    final app = items[index];
    final day = DateUtils.dateOnly(app.startTime);
    final prevDay = index > 0
        ? DateUtils.dateOnly(items[index - 1].startTime)
        : null;
    final showYear = prevDay == null || day.year != prevDay.year;
    final showDay = prevDay == null || day != prevDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showYear)
          Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : AppSpacing.sp16,
              bottom: AppSpacing.sp8,
            ),
            child: _YearHeaderLabel(day.year),
          ),
        if (showDay)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sp12),
            child: SectionLabel(
              DateUtilsHelper.formatDayHeader(day).toUpperCase(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
          child: AppointmentCard(
            appointment: app,
            // No live name map here — crewFor falls back to the record's
            // denormalized employeeNames.
            crew: crewFor(app, colorMap: colorMap),
            dimWhenCancelled: true,
            // Carries the caller's role rather than a hardcoded false: an
            // admin needs to reach a finished job's "Edit completed job"
            // button from here, which is where finished jobs actually live.
            onTap: () =>
                showEventDetails(context, app, showActions: widget.isAdmin),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorMap = ref.watch(employeeColorMapProvider);

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
          final years = _cachedYears;
          final employees = _cachedEmployees;
          final showFilters = HistoryFilterBar.hasFilters(
            years: years,
            employees: employees,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showFilters) _filterBar(years, employees),
              Expanded(
                child: _hasActiveFilter
                    ? _buildFiltered(colorMap)
                    : _buildPaged(state, loaded, fetchNextPage, colorMap),
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
  ) {
    return RefreshIndicator.adaptive(
      onRefresh: () async => _pagingController.refresh(),
      child: PagedListView<int, AppointmentRecord>(
        state: state,
        fetchNextPage: fetchNextPage,
        padding: const EdgeInsets.all(AppSpacing.sp12),
        builderDelegate: PagedChildBuilderDelegate<AppointmentRecord>(
          itemBuilder: (context, _, index) =>
              _historyItem(loaded, index, colorMap),
          firstPageProgressIndicatorBuilder: (_) => _skeleton(),
          firstPageErrorIndicatorBuilder: (_) => _errorState(
            state.error ?? Exception('history page load failed'),
            onRetry: _pagingController.refresh,
          ),
          noItemsFoundIndicatorBuilder: (_) => AppEmptyState(
            icon: Icons.history_outlined,
            title: context.l10n.common_noAppointmentsFound,
            body: context.l10n.common_tapToScheduleAnAppointment,
          ),
        ),
      ),
    );
  }

  Widget _buildFiltered(Map<String, Color> colorMap) {
    final query = widget.searchQuery.trim();
    // No text query — chip filters alone operate over the loaded pages.
    if (query.isEmpty) {
      return _filteredList(_filterLoaded(), colorMap);
    }

    // The local page filter fills the gap until the debounced server search settles.
    // It's computed lazily, so the settled `data` branch — which renders the server
    // results — doesn't end up re-filtering on every rebuild.
    Widget localOr(Widget Function() onEmpty) {
      final local = _filterLoaded();
      return local.isEmpty ? onEmpty() : _filteredList(local, colorMap);
    }

    if (_committedQuery != query) {
      return localOr(_skeleton);
    }

    return ref
        .watch(historySearchProvider(query))
        .when(
          data: (results) => _filteredList(_applyChips(results), colorMap),
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

  Widget _filteredList(
    List<AppointmentRecord> filtered,
    Map<String, Color> colorMap,
  ) {
    if (filtered.isEmpty) return _buildEmptyState(context);
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sp12),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _historyItem(filtered, index, colorMap),
    );
  }

  // This can't scroll itself — it lands inside ISP's SliverFillRemaining, and a nested
  // ListView there would throw an intrinsic-dimension error.
  Widget _skeleton() => const Padding(
    padding: EdgeInsets.all(AppSpacing.sp12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonListTile(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonListTile(),
        SizedBox(height: AppSpacing.sp8),
        SkeletonListTile(),
      ],
    ),
  );

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    final query = widget.searchQuery.trim();
    final hasChipFilter = _year != null || _employeeId != null;

    if (query.isNotEmpty && !hasChipFilter) {
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
      actionLabel: hasChipFilter ? l10n.clients_clearFilters : null,
      onAction: hasChipFilter ? _clearFilters : null,
    );
  }
}

/// Bold year separator that opens each year's group in the list.
class _YearHeaderLabel extends StatelessWidget {
  const _YearHeaderLabel(this.year);

  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '$year',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: AppSpacing.sp12),
        Expanded(
          child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ),
      ],
    );
  }
}
