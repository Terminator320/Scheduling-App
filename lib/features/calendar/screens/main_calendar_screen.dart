import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/master_detail_scaffold.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/sheet_helpers.dart';
import 'package:scheduling/features/calendar/widgets/fields/month_year_picker.dart';
import 'package:scheduling/features/calendar/widgets/views/app_calendar_view.dart';
import 'package:scheduling/features/calendar/widgets/views/event_details_view.dart';
import 'package:scheduling/features/calendar/widgets/views/event_list.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:table_calendar/table_calendar.dart';

class MainCalendar extends ConsumerStatefulWidget {
  const MainCalendar({
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final bool isAdmin;
  final String employeeId;

  @override
  ConsumerState<MainCalendar> createState() => _MainCalendarState();
}

class _MainCalendarState extends ConsumerState<MainCalendar> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final ValueNotifier<List<AppointmentRecord>> _selectedEvents = ValueNotifier(
    [],
  );

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  AppointmentRecord? _selectedAppointment;
  late AppointmentDateRange _appointmentRange;
  PhotoUploadNotifier? _uploadNotifier;
  bool _upgradingToAdmin = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _appointmentRange = AppointmentDateRange.visibleMonth(_focusedDay);
    _initStreams();
  }

  void _initStreams() {
    _uploadNotifier = ref.read(photoUploadNotifierProvider);
    _uploadNotifier?.latestFailure.addListener(_onUploadFailure);
  }

  @override
  void dispose() {
    _uploadNotifier?.latestFailure.removeListener(_onUploadFailure);
    _selectedEvents.dispose();
    super.dispose();
  }

  void _onUploadFailure() {
    final failure = _uploadNotifier?.latestFailure.value;
    if (failure == null || !mounted) return;
    final appointmentId = failure.appointmentId;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        backgroundColor: scheme.errorContainer,
        content: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.calendar_photoUploadFailedSnackbar,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: context.l10n.calendar_open,
          textColor: scheme.onErrorContainer,
          onPressed: () async {
            final appointment = await ref
                .read(appointmentsRepositoryProvider)
                .getAppointmentById(appointmentId);
            if (!mounted || appointment == null) return;
            await showEventDetails(
              context,
              appointment,
              showActions: widget.isAdmin,
            );
          },
        ),
      ),
    );
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedDay = now;
      _selectedDay = now;
      _appointmentRange = AppointmentDateRange.visibleMonth(now);
    });
  }

  void _setFocusedDay(DateTime day) {
    final newRange = AppointmentDateRange.visibleMonth(day);
    setState(() {
      _focusedDay = day;
      if (newRange != _appointmentRange) _appointmentRange = newRange;
    });
  }

  Map<DateTime, List<AppointmentRecord>>? _dayIndex;
  // Memoization key for _dayIndex: the appointments list last indexed.
  List<AppointmentRecord>? _indexedAppointments;

  Map<DateTime, List<AppointmentRecord>> _buildDayIndex(
    List<AppointmentRecord> source,
  ) {
    final index = <DateTime, List<AppointmentRecord>>{};
    for (final app in source) {
      final start = app.startTime;
      final key = DateTime(start.year, start.month, start.day);
      (index[key] ??= <AppointmentRecord>[]).add(app);
    }
    for (final list in index.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return index;
  }

  List<AppointmentRecord> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _dayIndex?[key] ?? const <AppointmentRecord>[];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      final newRange = AppointmentDateRange.visibleMonth(focusedDay);
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        if (newRange != _appointmentRange) _appointmentRange = newRange;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final myAppointmentsKey = (
      employeeId: widget.employeeId,
      range: _appointmentRange,
    );
    final appointmentsAsync = widget.isAdmin
        ? ref.watch(appointmentsInRangeProvider(_appointmentRange))
        : ref.watch(myAppointmentsProvider(myAppointmentsKey));
    final userName = ref.watch(currentUserNameProvider);

    void onAsyncChange(
      AsyncValue<List<AppointmentRecord>>? previous,
      AsyncValue<List<AppointmentRecord>> next,
    ) {
      if (next is AsyncError && previous is! AsyncError) {
        ref
            .read(loggerProvider)
            .warn(
              'APPT-LOAD appointments stream error',
              next.error,
              next.stackTrace,
            );
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introLoadAppointments,
                tag: 'APPT-LOAD',
                error: next.error ?? Exception('unknown'),
              ),
            );
      }
    }

    if (widget.isAdmin) {
      ref.listen(appointmentsInRangeProvider(_appointmentRange), onAsyncChange);
    } else {
      ref.listen(myAppointmentsProvider(myAppointmentsKey), onAsyncChange);
    }

    if (!widget.isAdmin) {
      void upgradeIfAdmin(String? role) {
        if (role != 'admin' || !mounted || _upgradingToAdmin) return;
        _upgradingToAdmin = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(
            AppRoutes.mainCalendar,
            arguments: MainCalendarArgs(
              isAdmin: true,
              employeeId: widget.employeeId,
            ),
          );
        });
      }

      ref.listen<AsyncValue<String>>(
        userRoleProvider,
        (_, next) => upgradeIfAdmin(next.value),
      );
      upgradeIfAdmin(ref.read(userRoleProvider).value);
    }

    final employees =
        ref.watch(allUsersStreamProvider).asData?.value ?? const [];
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);

    final visibleAppointments = appointmentsAsync.when(
      data: (data) => data,
      loading: () => const <AppointmentRecord>[],
      error: (err, stack) {
        ref.read(loggerProvider).warn('appointments stream error', err, stack);
        return const <AppointmentRecord>[];
      },
    );


    if (!identical(visibleAppointments, _indexedAppointments)) {
      _indexedAppointments = visibleAppointments;
      _dayIndex = _buildDayIndex(visibleAppointments);
    }

    final selectedDay = _selectedDay ?? _focusedDay;
    final selectedEvents = _getEventsForDay(selectedDay);
    _selectedEvents.value = selectedEvents;

    final isLoading = appointmentsAsync.isLoading;
    final locale = Localizations.localeOf(context).toString();
    final monthLabel = DateFormat.yMMMM(locale).format(_focusedDay);
    final jobLabel =
        '${selectedEvents.length} ${context.l10n.calendar_appointments}';

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        automaticallyImplyLeading: false,
        title: Text(
          context.l10n.common_calendar,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _goToToday,
            child: Text(
              context.l10n.calendar_today,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.menu, color: scheme.onPrimary),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Semantics(
                  button: true,
                  label: context.l10n.calendar_selectDate,
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await MonthYearPicker.show(
                        context,
                        _focusedDay,
                      );
                      if (picked != null) _setFocusedDay(picked);
                    },
                    child: Text(
                      monthLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onPrimary.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                ),
                Text(
                  jobLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onPrimary.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: () async {
                await showAddEventPopup(
                  context,
                  initialDate: _selectedDay ?? _focusedDay,
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
      endDrawer: SettingsDrawer(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        userName: userName,
      ),
      body: AdaptiveShell(
        currentDestination: AdaptiveDestination.calendar,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        userName: userName,
        child: SafeArea(
          child: MasterDetailScaffold(
            master: _content(
              isLoading: isLoading,
              colorMap: colorMap,
              nameMap: nameMap,
              employees: employees,
            ),
            detail: _selectedAppointment == null
                ? null
                : EventDetailsView(
                    key: ValueKey(_selectedAppointment!.id),
                    appointment: _selectedAppointment!,
                    showActions: widget.isAdmin,
                    onClose: (_) => setState(() => _selectedAppointment = null),
                  ),
            placeholder: _buildDetailPlaceholder(),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPlaceholder() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.calendar_selectAnAppointmentToViewDetails,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _onAppointmentTap(AppointmentRecord appointment) {
    if (context.isWide) {
      setState(() => _selectedAppointment = appointment);
    } else {
      showEventDetails(context, appointment, showActions: widget.isAdmin);
    }
  }

  Widget _content({
    required bool isLoading,
    required Map<String, Color> colorMap,
    required Map<String, String> nameMap,
    required List<EmployeeRecord> employees,
  }) {
    final screenSize = MediaQuery.sizeOf(context);
    final isTablet = context.isWide;

    return Column(
      children: [
        AppCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: _onDaySelected,
          rowHeight: isTablet
              ? screenSize.height * 0.08
              : screenSize.height * 0.065,
          eventLoader: _getEventsForDay,
          onCalendarCreated: (_) {},
          onPageChanged: _setFocusedDay,
          employees: employees,
          employeeColorMap: colorMap,
        ),
        const SizedBox(height: AppSpacing.sp12),
        const Divider(),
        EventList(
          events: _selectedEvents,
          nameMap: nameMap,
          colorMap: colorMap,
          isLoading: isLoading,
          isAdmin: widget.isAdmin,
          selectedAppointmentId: _selectedAppointment?.id,
          onAppointmentTap: _onAppointmentTap,
        ),
      ],
    );
  }
}
