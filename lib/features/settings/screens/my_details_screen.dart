import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/features/settings/application/my_details_providers.dart';
import 'package:scheduling/features/settings/services/self_email_service.dart';
import 'package:scheduling/features/settings/widgets/dialogs/change_email_dialog.dart';
import 'package:scheduling/features/settings/widgets/sections/my_availability_section.dart';
import 'package:scheduling/features/settings/widgets/sections/my_identity_section.dart';
import 'package:scheduling/features/settings/widgets/sections/my_scheduling_section.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/centered_error_text.dart';

/// The one surface where a person edits their OWN record.
///
/// It exists because `/users` `allow update` is otherwise admin-only, and two
/// grants have no other way to be exercised: the `private/emergency`
/// subcollection (admin OR the owner) and P5's self-service clause
/// (`isSelf() && isAvailabilityOnlyChange()`).
///
/// Deliberately not a general profile editor. Everything not on one of those
/// two grants — name, role, job title, crew colour, status — stays admin-only
/// on the Team sheet, and a control for it here would fail with an opaque
/// `permission-denied`.
///
/// **Two save behaviours on one screen, on purpose** (owner call, 2026-08-10).
/// The identity fields are explicitly saved behind a dirty-gated Save/Discard
/// bar; the availability controls apply immediately. See the section widgets.
class MyDetailsScreen extends ConsumerStatefulWidget {
  const MyDetailsScreen({super.key});

  @override
  ConsumerState<MyDetailsScreen> createState() => _MyDetailsScreenState();
}

class _MyDetailsScreenState extends ConsumerState<MyDetailsScreen> {
  bool _seeded = false;
  bool _isSaving = false;

  List<bool> _workingDays = kDefaultWorkingDays;
  int _workStartMinutes = kDefaultWorkStartMinutes;
  int _workEndMinutes = kDefaultWorkEndMinutes;
  bool _onCall = false;

  /// The phone as STORED, not as typed.
  ///
  /// An availability write is one patch that carries every self-service key, so
  /// it has to send a phone — and it must be the committed one. Sending the
  /// identity controller's text instead would make toggling a working day
  /// silently commit a half-typed phone number, which is exactly the auto-save
  /// the identity bar exists to prevent.
  String _storedPhone = '';

  /// Carried through every self write untouched — the toggle for it lives in
  /// Settings, but the rules' `hasOnly` means the patch must still name it, and
  /// sending a guessed default would flip somebody's push setting.
  bool _travelAlertsEnabled = true;

  /// Seeds once, from the first record that arrives — a later snapshot must not
  /// overwrite what the person is part-way through changing.
  void _seed(EmployeeRecord record) {
    if (_seeded) return;
    _seeded = true;
    _workingDays = normalizeWorkingDays(record.workingDays);
    _workStartMinutes = record.workStartMinutes;
    _workEndMinutes = record.workEndMinutes;
    _onCall = record.onCall;
    _storedPhone = record.phone;
    _travelAlertsEnabled = record.travelAlertsEnabled;
  }

  /// Identity save — the emergency contact (subcollection) AND the phone (users
  /// doc). Two stores, so both are awaited before the success notice.
  Future<void> _saveIdentity(String docId, MyIdentityEdit edit) async {
    // Set synchronously before the first await, or a double-tap starts a
    // second concurrent write.
    if (_isSaving) return;
    FocusScope.of(context).unfocus();

    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);

    // An awaited Firestore write offline only resolves on server ack, so
    // without this Save would spin until the connection returns.
    if (guardedOffline(context, ref, intro: l10n.error_introSaveMyDetails)) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(employeesRepositoryProvider);
      await repository.saveEmergencyContact(
        docId,
        EmergencyContact(
          contact: edit.emergencyContact,
          phone: edit.emergencyPhone,
        ),
      );
      await repository.updateSelfDetails(
        docId: docId,
        phone: edit.phone,
        workingDays: _workingDays,
        workStartMinutes: _workStartMinutes,
        workEndMinutes: _workEndMinutes,
        onCall: _onCall,
        // Not the person's to change here — Settings owns that toggle, so the
        // stored value is carried through untouched.
        travelAlertsEnabled: _travelAlertsEnabled,
      );
      if (!mounted) return;
      setState(() => _storedPhone = edit.phone);
      notices.success(l10n.common_changesSaved);
    } catch (error, stackTrace) {
      ref
          .read(loggerProvider)
          .warn('ME-SAVE identity save failed', error, stackTrace);
      if (!mounted) return;
      notices.error(
        composeErrorNotice(
          context,
          intro: l10n.error_introSaveMyDetails,
          error: error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Availability applies immediately (P5 spec).
  ///
  /// Optimistic: the local state moves first so a switch doesn't lag a
  /// Firestore round trip, and a failure rolls it back and says so. Rolling
  /// back matters more than the latency — a toggle left showing the new value
  /// after a refused write is a lie about what the server holds.
  Future<void> _applyAvailability(
    String docId,
    List<bool> days,
    int start,
    int end, {
    required bool onCall,
  }) async {
    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);

    final previousDays = _workingDays;
    final previousStart = _workStartMinutes;
    final previousEnd = _workEndMinutes;
    final previousOnCall = _onCall;

    void rollBack() {
      setState(() {
        _workingDays = previousDays;
        _workStartMinutes = previousStart;
        _workEndMinutes = previousEnd;
        _onCall = previousOnCall;
      });
    }

    setState(() {
      _workingDays = days;
      _workStartMinutes = start;
      _workEndMinutes = end;
      _onCall = onCall;
    });

    if (guardedOffline(context, ref, intro: l10n.error_introSaveAvailability)) {
      rollBack();
      return;
    }

    try {
      await ref
          .read(employeesRepositoryProvider)
          .updateSelfDetails(
            docId: docId,
            phone: _storedPhone,
            workingDays: days,
            workStartMinutes: start,
            workEndMinutes: end,
            onCall: onCall,
            travelAlertsEnabled: _travelAlertsEnabled,
          );
    } catch (error, stackTrace) {
      ref
          .read(loggerProvider)
          .warn('ME-SAVE availability failed', error, stackTrace);
      if (!mounted) return;
      rollBack();
      notices.error(
        composeErrorNotice(
          context,
          intro: l10n.error_introSaveAvailability,
          error: error,
        ),
      );
    }
  }

  /// Collects the new address + a re-auth password, then moves BOTH stores
  /// through the callable.
  ///
  /// Never a users-doc write: `email` is a sign-in identity and is deliberately
  /// absent from the self-service rules allowlist, so Auth and Firestore move
  /// together through `changeEmployeeEmail` or not at all.
  Future<void> _changeEmail(String docId, String currentEmail) async {
    if (_isSaving) return;
    final draft = await showChangeEmailSheet(
      context,
      currentEmail: currentEmail,
    );
    if (draft == null || !mounted) return;

    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);

    if (guardedOffline(context, ref, intro: l10n.error_introChangeEmail)) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(selfEmailServiceProvider)
          .changeOwnEmail(
            docId: docId,
            email: draft.email,
            password: draft.password,
          );
      if (!mounted) return;
      notices.success(l10n.common_changesSaved);
    } on AuthFailure catch (failure, stackTrace) {
      // Typed branch first: a wrong password here is an expected outcome, and
      // authFailure buckets it as a breadcrumb rather than an error record.
      ref
          .read(loggerProvider)
          .authFailure('ME-EMAIL change failed', failure, failure, stackTrace);
      if (!mounted) return;
      notices.error(failure.toLocalizedMessage(context));
    } catch (error, stackTrace) {
      ref
          .read(loggerProvider)
          .warn('ME-EMAIL change failed', error, stackTrace);
      if (!mounted) return;
      notices.error(
        composeErrorNotice(
          context,
          intro: l10n.error_introChangeEmail,
          error: error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// `maxJobsPerDay` is admin-owned, so this goes through the ordinary
  /// whole-record admin save rather than `updateSelfDetails` — the self
  /// allowlist does not name it, and `hasOnly` would reject the write.
  Future<void> _saveMaxJobs(
    String docId,
    EmployeeRecord record,
    int value,
  ) async {
    if (_isSaving) return;
    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);

    if (guardedOffline(context, ref, intro: l10n.error_introSaveMyDetails)) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(employeesRepositoryProvider)
          .updateEmployee(
            docId: docId,
            employee: record.copyWith(maxJobsPerDay: value),
          );
      if (!mounted) return;
      notices.success(l10n.common_changesSaved);
    } catch (error, stackTrace) {
      ref
          .read(loggerProvider)
          .warn('ME-SAVE max jobs failed', error, stackTrace);
      if (!mounted) return;
      notices.error(
        composeErrorNotice(
          context,
          intro: l10n.error_introSaveMyDetails,
          error: error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Switch on the AsyncValue, never on `.value`: this provider awaits a
    // findUserByUid wrapped in retryAsync (500ms + 1500ms), so `.value` is null
    // for up to ~2s on a cold read. Treating that null as an error filled the
    // screen with "Something went wrong" before the form appeared, and built
    // the drawer with the employee nav set for an admin.
    final identity = ref.watch(activeUserIdentityProvider);

    return Scaffold(
      appBar: AppTopBar(
        title: l10n.settings_myDetails,
        compact: context.isLandscape,
        onBack: () => Navigator.maybePop(context),
        actions: const [AppHeaderPair()],
      ),
      endDrawer: AppNavDrawer(
        isAdmin: identity.value?.role == 'admin',
        employeeId: identity.value?.docId ?? '',
      ),
      body: identity.when(
        loading: () => const Center(child: AdaptiveProgressIndicator(size: 32)),
        error: (_, _) => Center(
          child: CenteredErrorText(message: l10n.error_somethingWentWrong),
        ),
        // A settled null identity — signed out or inactive — is the only real
        // error here.
        data: (value) => value == null
            ? Center(
                child: CenteredErrorText(
                  message: l10n.error_somethingWentWrong,
                ),
              )
            : _body(value.docId, isAdmin: value.role == 'admin'),
      ),
    );
  }

  Widget _body(String docId, {required bool isAdmin}) {
    final l10n = context.l10n;
    final record = ref.watch(myEmployeeRecordProvider);
    final emergency = ref.watch(emergencyContactProvider(docId));

    // Both reads must land before the form is safe to show: the identity
    // section seeds its controllers ONCE, and a blank-by-default field over a
    // stored value invites the person to save the blank back.
    if (record == null || emergency.isLoading) {
      return const Center(child: AdaptiveProgressIndicator(size: 32));
    }
    // A failed emergency read is "we couldn't load it", never "you have none
    // on file" — the same distinction the edit-person sheet draws.
    if (emergency.hasError) {
      return Center(
        child: CenteredErrorText(message: l10n.error_somethingWentWrong),
      );
    }

    _seed(record);
    final contact = emergency.requireValue;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sp16),
      children: [
        MyIdentitySection(
          email: record.email,
          initialPhone: record.phone,
          initialEmergencyContact: contact.contact,
          initialEmergencyPhone: contact.phone,
          isSaving: _isSaving,
          onSave: (edit) => _saveIdentity(docId, edit),
          onChangeEmail: () => _changeEmail(docId, record.email),
        ),
        const SizedBox(height: AppSpacing.sp24),
        Text(
          l10n.settings_myDetailsEmergencyBlurb,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),
        MyAvailabilitySection(
          workingDays: _workingDays,
          workStartMinutes: _workStartMinutes,
          workEndMinutes: _workEndMinutes,
          onCall: _onCall,
          conflictDays: ref.watch(
            myAvailabilityConflictProvider(
              AvailabilityChange(
                previousWorkingDays: normalizeWorkingDays(record.workingDays),
                nextWorkingDays: _workingDays,
              ),
            ),
          ),
          onChanged: (days, start, end, {required onCall}) =>
              _applyAvailability(docId, days, start, end, onCall: onCall),
        ),
        const SizedBox(height: AppSpacing.sp24),
        MySchedulingSection(
          isAdmin: isAdmin,
          maxJobsPerDay: record.maxJobsPerDay,
          onChanged: (value) => _saveMaxJobs(docId, record, value),
        ),
        const SizedBox(height: AppSpacing.sp32),
      ],
    );
  }
}
