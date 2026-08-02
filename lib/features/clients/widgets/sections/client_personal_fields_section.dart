import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Shared name and contact field block, used by both the add-client sheet and the edit
/// form, so field behavior stays centralized in one place.
class ClientPersonalFieldsSection extends StatelessWidget {
  const ClientPersonalFieldsSection({
    required this.nameController,
    required this.firstNameController,
    required this.lastNameController,
    required this.phoneController,
    required this.mobileController,
    required this.emailController,
    required this.onClearError,
    super.key,
    this.nameError,
    this.emailError,
  });

  final TextEditingController nameController;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController phoneController;
  final TextEditingController mobileController;
  final TextEditingController emailController;
  final String? nameError;
  final String? emailError;
  final void Function(String key) onClearError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_customerName,
            controller: nameController,
            required: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            maxLength: TextLimits.personName,
            errorText: nameError,
            onChanged: (_) => onClearError('name'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_firstName,
            controller: firstNameController,
            optional: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            maxLength: TextLimits.firstName,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_lastName,
            controller: lastNameController,
            optional: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
            maxLength: TextLimits.lastName,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_phone,
            controller: phoneController,
            keyboard: TextInputType.phone,
            inputFormatters: const [PhoneInputFormatter()],
            textInputAction: TextInputAction.next,
            optional: true,
            autofillHints: const [AutofillHints.telephoneNumber],
            maxLength: TextLimits.phone,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_mobile,
            controller: mobileController,
            keyboard: TextInputType.phone,
            inputFormatters: const [PhoneInputFormatter()],
            textInputAction: TextInputAction.next,
            optional: true,
            autofillHints: const [AutofillHints.telephoneNumber],
            maxLength: TextLimits.mobile,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.common_email,
            controller: emailController,
            keyboard: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            optional: true,
            autofillHints: const [AutofillHints.email],
            maxLength: TextLimits.email,
            errorText: emailError,
            onChanged: (_) => onClearError('email'),
          ),
        ),
      ],
    );
  }
}
