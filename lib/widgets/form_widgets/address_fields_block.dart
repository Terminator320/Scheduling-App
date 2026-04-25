import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/address_suggestion.dart';
import '../../services/google_places_service.dart';
import 'form_helpers.dart';
import 'labeled_text_field.dart';

/// Address search bar plus structured fields (street, city, province, postal
/// code). Tapping a suggestion fills the four fields from Google Places.
class AddressFieldsBlock extends StatefulWidget {
  const AddressFieldsBlock({
    super.key,
    required this.streetController,
    required this.cityController,
    required this.provinceController,
    required this.postalCodeController,
    this.streetError,
    this.cityError,
    this.provinceError,
    this.postalCodeError,
    this.onChanged,
    this.requireStreet = true,
  });

  final TextEditingController streetController;
  final TextEditingController cityController;
  final TextEditingController provinceController;
  final TextEditingController postalCodeController;
  final String? streetError;
  final String? cityError;
  final String? provinceError;
  final String? postalCodeError;
  final VoidCallback? onChanged;
  final bool requireStreet;

  @override
  State<AddressFieldsBlock> createState() => _AddressFieldsBlockState();
}

class _AddressFieldsBlockState extends State<AddressFieldsBlock> {
  final _service = GooglePlacesService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<AddressSuggestion> _suggestions = [];
  bool _isLoading = false;
  String? _serviceError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
        _serviceError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(value));
  }

  Future<void> _fetch(String query) async {
    setState(() {
      _isLoading = true;
      _serviceError = null;
    });
    try {
      final results = await _service.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _isLoading = false;
        _serviceError = "Address lookup failed";
      });
    }
  }

  Future<void> _selectSuggestion(AddressSuggestion s) async {
    setState(() {
      _suggestions = [];
      _isLoading = true;
      _serviceError = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final details = await _service.getPlaceDetails(s.placeId);
      if (!mounted) return;
      setState(() {
        widget.streetController.text = details.street;
        widget.cityController.text = details.city;
        widget.provinceController.text =
            details.province.isNotEmpty ? details.province : 'QC';
        widget.postalCodeController.text = details.postalCode;
        _searchController.clear();
        _isLoading = false;
      });
      widget.onChanged?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _serviceError = "Could not load address details";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formLabel(context, "Search address", optional: true),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: formInputDecoration(
            context,
            "Type to search an address",
          ).copyWith(
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: _suggestions
                  .map(
                    (s) => ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        s.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onTap: () => _selectSuggestion(s),
                    ),
                  )
                  .toList(),
            ),
          ),
        if (_serviceError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _serviceError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
            ),
          ),
        const SizedBox(height: 16),
        LabeledTextField(
          label: "Street",
          controller: widget.streetController,
          required: widget.requireStreet,
          autofillHints: const [AutofillHints.streetAddressLine1],
          errorText: widget.streetError,
          onChanged: (_) => widget.onChanged?.call(),
        ),
        const SizedBox(height: 12),
        LabeledTextField(
          label: "City",
          controller: widget.cityController,
          autofillHints: const [AutofillHints.addressCity],
          errorText: widget.cityError,
          onChanged: (_) => widget.onChanged?.call(),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: LabeledTextField(
                label: "Province",
                controller: widget.provinceController,
                autofillHints: const [AutofillHints.addressState],
                errorText: widget.provinceError,
                onChanged: (_) => widget.onChanged?.call(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: LabeledTextField(
                label: "Postal code",
                controller: widget.postalCodeController,
                autofillHints: const [AutofillHints.postalCode],
                errorText: widget.postalCodeError,
                onChanged: (_) => widget.onChanged?.call(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
