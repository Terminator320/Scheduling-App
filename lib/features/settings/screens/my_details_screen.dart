
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/feedback/centered_error_text.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';

/// The one surface where a person edits their OWN record.
///
/// It exists because `emergencyContact`/`emergencyPhone` moved off the users
/// doc into `users/{id}/private/emergency`, which rules gate to an admin and
/// the owner. Without this screen the owner half of that grant would have no
/// way to be exercised. Everything else about a person stays admin-only — this
/// is deliberately not a general profile editor.
class MyDetailsScreen extends ConsumerStatefulWidget {
  const MyDetailsScreen({super.key});

  @override
  ConsumerState<MyDetailsScreen> createState() => _MyDetailsScreenState();
}

class _MyDetailsScreenState extends ConsumerState<MyDetailsScreen> {
  final _contactController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _seeded = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _contactController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Seeds once, from the first snapshot that arrives — a later snapshot must
  /// not overwrite what the user is part-way through typing.
  void _seed(EmergencyContact contact) {
    if (_seeded) return;
    _seeded = true;
    _contactController.text = contact.contact;
    _phoneController.text = contact.phone;
  }

  Future<void> _save(String docId) async {
    // Set synchronously before the first await, or a double-tap starts a
    // second concurrent write.
    if (_isSaving) return;
    FocusScope.of(context).unfocus();

    final l10n = context.l10n;
    final notices = ref.read(noticeServiceProvider);

    // An awaited Firestore write offline only resolves on server ack, so
    // without this Save would spin until the connection returns.
    if (guardedOffline(
      context,
      ref,
      intro: context.l10n.error_introSaveMyDetails,
    )) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(employeesRepositoryProvider)
          .saveEmergencyContact(
            docId,
            EmergencyContact(
              contact: _contactController.text,
              phone: _phoneController.text,
            ),
          );
      if (!mounted) return;
      notices.success(l10n.common_changesSaved);
    } catch (error, stackTrace) {
      ref
          .read(loggerProvider)
          .warn('ME-SAVE emergency contact failed', error, stackTrace);
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
            : _body(value.docId),
      ),
    );
  }

  Widget _body(String docId) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return ref
        .watch(emergencyContactProvider(docId))
        .when(
          loading: () =>
              const Center(child: AdaptiveProgressIndicator(size: 32)),
          // A read failure here is "we couldn't load it", never "you have none
          // on file" — showing empty fields would invite the user to overwrite
          // a contact that is actually stored.
          error: (_, _) => Center(
            child: CenteredErrorText(message: l10n.error_somethingWentWrong),
          ),
          data: (contact) {
            _seed(contact);
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.sp16),
              children: [
                MonoSectionLabel(l10n.employees_sectionEmergency),
                const SizedBox(height: AppSpacing.sp8),
                Text(
                  l10n.settings_myDetailsEmergencyBlurb,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sp16),
                SheetPanel(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sp16),
                      child: Column(
                        children: [
                          LabeledTextField(
                            key: const Key('myEmergencyContact'),
                            label: l10n.employees_emergencyContact,
                            controller: _contactController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            maxLength: TextLimits.employeeEmergencyContact,
                          ),
                          const SizedBox(height: AppSpacing.sp16),
                          LabeledTextField(
                            key: const Key('myEmergencyPhone'),
                            label: l10n.employees_emergencyPhone,
                            controller: _phoneController,
                            keyboard: TextInputType.phone,
                            inputFormatters: const [PhoneInputFormatter()],
                            maxLength: TextLimits.phone,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sp24),
                AnimatedLoadingButton(
                  label: l10n.common_save,
                  isLoading: _isSaving,
                  onPressed: () => _save(docId),
                ),
                const SizedBox(height: AppSpacing.sp32),
              ],
            );
          },
        );
  }
}
