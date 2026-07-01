import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_tile.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/clients/widgets/sections/history_filter_bar.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Paginated (newest-first) history list. Pages load on scroll; year/employee
/// chip filters and the search query operate over the already-loaded pages
/// (same intentional client-side model as the clients list).
class AppointmentHistoryView extends ConsumerStatefulWidget {
  const AppointmentHistoryView({required this.searchQuery, super.key});

  final String searchQuery;

  @override
  ConsumerState<AppointmentHistoryView> createState() =>
      _AppointmentHistoryViewState();
}

class _AppointmentHistoryViewState
    extends ConsumerState<AppointmentHistoryView> {
  static const int _pageSize = 25;
  // Debounce before firing the comprehensive history search (mirrors the
  // clients list); the loaded-page filter covers the gap so typing feels instant.
  final _searchDebounce = Debouncer(const Duration(milliseconds: 250));

  int? _year;
  String? _employeeId;

  String _committedQuery = '';

  // Memoized year/employee filter options — recomputed only when a new page
  // arrives (keyed on PagingState.pages identity), not on every rebuild from
  // a search/filter setState. Mirrors main_calendar_screen's _dayIndex memo.
  List<List<AppointmentRecord>>? _filterOptionsPages;
  List<int> _cachedYears = const [];
  List<HistoryEmployeeOption> _cachedEmployees = const [];

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
    // Load the first page up front so search/filter has data even when the
    // view opens directly into a filtered state — the PagedListView that would
    // otherwise trigger the initial fetch isn't mounted while filtering.
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
          .read(appointmentsRepositoryProvider)
          .fetchHistoryPage(after: after, limit: _pageSize);
    } catch (e, st) {
      ref
          .read(loggerProvider)
          .warn('HIST-LOAD history page fetch error', e, st);
      rethrow;
    }
  }

  @override
  void didUpdateWidget(covariant AppointmentHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery.trim() == oldWidget.searchQuery.trim()) return;
    _scheduleSearch();
  }

  // Restart the debounce on every query change; clearing commits instantly.
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

  // Year/employee chip filters only (no text search). Applied on top of either
  // the loaded pages or the server-backed search results.
  List<AppointmentRecord> _applyChips(List<AppointmentRecord> appointments) {
    return appointments.where((a) {
      if (_year != null && a.startTime.year != _year) return false;
      if (_employeeId != null && !a.employeeIds.contains(_employeeId)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<AppointmentRecord> _applyFilters(List<AppointmentRecord> appointments) {
    final hasQuery = widget.searchQuery.trim().isNotEmpty;
    // Accent-folded text + digits-only phone matching — same rule as the
    // clients list, so a client's phone number finds their appointments.
    final qText = ClientSearchPolicy.normalize(widget.searchQuery);
    final qDigits = ClientSearchPolicy.digitsOnly(widget.searchQuery);
    return _applyChips(appointments).where((a) {
      if (!hasQuery) return true;
      if (qText.isEmpty && qDigits.isEmpty) return false;
      final matchesClient =
          qText.isNotEmpty &&
          ClientSearchPolicy.normalize(a.clientName).contains(qText);
      final matchesEmployee =
          qText.isNotEmpty &&
          a.employeeNames.any(
            (e) => ClientSearchPolicy.normalize(e).contains(qText),
          );
      final matchesPhone =
          qDigits.isNotEmpty &&
          ClientSearchPolicy.digitsOnly(a.clientPhone).contains(qDigits);
      return matchesClient || matchesEmployee || matchesPhone;
    }).toList();
  }

  // Builds one history entry with the year/day headers that open its group,
  // derived by comparing against the previous item in [items]. Shared by the
  // paged (unfiltered) and filtered list paths so grouping looks identical.
  Widget _historyItem(
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
          child: AppointmentTile(
            appointment: app,
            employeeColorMap: colorMap,
            showActions: false,
            alwaysShowChip: true,
            dimWhenCancelled: true,
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
              if (showFilters)
                Padding(
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
                ),
              Expanded(
                child: _hasActiveFilter
                    ? _buildFiltered(loaded, colorMap)
                    : _buildPaged(state, fetchNextPage, colorMap),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaged(
    PagingState<int, AppointmentRecord> state,
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
              _historyItem(state.items ?? const [], index, colorMap),
          firstPageProgressIndicatorBuilder: (_) => _skeleton(),
          firstPageErrorIndicatorBuilder: (_) => Center(
            child: Text(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introLoadHistory,
                tag: 'HIST-LOAD',
                error: state.error ?? Exception('history page load failed'),
              ),
            ),
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

  Widget _buildFiltered(
    List<AppointmentRecord> loaded,
    Map<String, Color> colorMap,
  ) {
    final query = widget.searchQuery.trim();
    // No text query — chip filters alone operate over the loaded pages.
    if (query.isEmpty) {
      return _filteredList(_applyFilters(loaded), colorMap);
    }

    // A search reaches the whole history window via the database (not just the
    // loaded pages). The loaded-page filter fills the gap until the debounce
    // settles and the server result arrives.
    // The loaded-page fallback, computed lazily: the steady-state `data` branch
    // renders the server results and never needs it, so don't filter the loaded
    // pages on every rebuild once the search has settled.
    Widget localOr(Widget Function() onEmpty) {
      final local = _applyFilters(loaded);
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
          // A failed search shouldn't read as "no history": when the local
          // fallback is also empty, surface an error, not the empty state.
          // Composes without logging (this is a builder).
          error: (e, _) => localOr(() => _searchError(e)),
        );
  }

  Widget _searchError(Object error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sp24),
      child: Text(
        composeErrorNotice(
          context,
          intro: context.l10n.error_introLoadHistory,
          tag: 'HIST-LOAD',
          error: error,
        ),
        textAlign: TextAlign.center,
      ),
    ),
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

  // Non-scrolling: lands inside ISP's SliverFillRemaining, where a nested
  // ListView would throw an intrinsic-dimension error.
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
