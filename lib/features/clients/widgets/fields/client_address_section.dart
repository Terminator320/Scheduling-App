import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/clients/widgets/fields/address_grid_fields.dart';
import 'package:scheduling/features/maps/address_field_filler.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// The street-address block shared by the add- and edit-client forms: an
/// autocomplete street field, an apt/unit field, and the city / province /
/// postal-code / country grid. The individual controllers are owned by the
/// parent form. On autocomplete selection it splits the chosen address across
/// those controllers and asks the parent to clear any address error via
/// [onAddressErrorCleared].
class ClientAddressSection extends StatefulWidget {
  const ClientAddressSection({
    required this.addressController,
    required this.aptController,
    required this.cityController,
    required this.provinceController,
    required this.postalCodeController,
    required this.countryController,
    required this.isRequired,
    required this.onAddressErrorCleared,
    this.errorText,
    super.key,
  });

  final TextEditingController addressController;
  final TextEditingController aptController;
  final TextEditingController cityController;
  final TextEditingController provinceController;
  final TextEditingController postalCodeController;
  final TextEditingController countryController;
  final bool isRequired;
  final String? errorText;
  final VoidCallback onAddressErrorCleared;

  @override
  State<ClientAddressSection> createState() => _ClientAddressSectionState();
}

class _ClientAddressSectionState extends State<ClientAddressSection> {
  // Microtask: let the autocomplete finish writing the controller first, then
  // split the chosen address across the individual fields.
  void _handleAddressSelected() {
    Future<void>.microtask(() {
      if (!mounted) return;
      fillAddressControllersFromText(
        widget.addressController.text,
        address: widget.addressController,
        apt: widget.aptController,
        city: widget.cityController,
        province: widget.provinceController,
        postalCode: widget.postalCodeController,
        country: widget.countryController,
      );
      widget.onAddressErrorCleared();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetFocusScroll(
          child: AddressAutocompleteField(
            controller: widget.addressController,
            required: widget.isRequired,
            errorText: widget.errorText,
            onChanged: (_) => widget.onAddressErrorCleared(),
            onAddressSelected: (_) => _handleAddressSelected(),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_aptUnit,
            controller: widget.aptController,
            optional: true,
            maxLength: TextLimits.aptUnit,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        AddressGridFields(
          cityController: widget.cityController,
          provinceController: widget.provinceController,
          postalCodeController: widget.postalCodeController,
          countryController: widget.countryController,
        ),
      ],
    );
  }
}
