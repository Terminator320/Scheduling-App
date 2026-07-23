import 'package:flutter/material.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

// City/province and postal-code/country grid (shared by add/edit forms).
class AddressGridFields extends StatelessWidget {
  const AddressGridFields({
    required this.cityController,
    required this.provinceController,
    required this.postalCodeController,
    required this.countryController,
    super.key,
  });

  final TextEditingController cityController;
  final TextEditingController provinceController;
  final TextEditingController postalCodeController;
  final TextEditingController countryController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.common_city,
                  controller: cityController,
                  autofillHints: const [AutofillHints.addressCity],
                  maxLength: TextLimits.city,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.common_province,
                  controller: provinceController,
                  autofillHints: const [AutofillHints.addressState],
                  maxLength: TextLimits.province,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.common_postalCode,
                  controller: postalCodeController,
                  autofillHints: const [AutofillHints.postalCode],
                  maxLength: TextLimits.postalCode,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.clients_country,
                  controller: countryController,
                  autofillHints: const [AutofillHints.countryName],
                  maxLength: TextLimits.country,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
