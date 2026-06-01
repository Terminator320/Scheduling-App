import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/maps/data/google_places_repository.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/features/maps/domain/models/address_suggestion.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:uuid/uuid.dart';

class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    required this.controller,
    super.key,
    this.label,
    this.required = false,
    this.optional = false,
    this.errorText,
    this.onChanged,
    this.onAddressSelected,
  });

  final TextEditingController controller;
  final String? label;
  final bool required;
  final bool optional;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onAddressSelected;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _service = GooglePlacesRepository();
  static const _uuid = Uuid();
  Timer? _debounce;
  List<AddressSuggestion> _suggestions = [];
  bool _isLoading = false;
  String? _serviceError;
  bool _suppressFetch = false;
  String? _sessionToken;
  String _lastTypedApt = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _ensureSessionToken() => _sessionToken ??= _uuid.v4();

  void _onTextChanged(String value) {
    widget.onChanged?.call(value);
    if (_suppressFetch) {
      _suppressFetch = false;
      return;
    }

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

  String _localizedErrorFor(
    Object error,
    BuildContext context,
    String fallback,
  ) {
    if (error is Failure) return error.toLocalizedMessage(context);
    return fallback;
  }

  Future<void> _fetch(String query) async {
    setState(() {
      _isLoading = true;
      _serviceError = null;
    });
    _lastTypedApt = AddressParser.splitApt(query)?.apt ?? '';
    try {
      final results = await _service.autocomplete(
        query,
        sessionToken: _ensureSessionToken(),
      );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _isLoading = false;
        _serviceError = _localizedErrorFor(
          e,
          context,
          context.l10n.error_addressLookupFailed,
        );
      });
    }
  }

  Future<void> _selectSuggestion(AddressSuggestion s) async {
    _suppressFetch = true;
    widget.controller.text = s.description;
    setState(() {
      _suggestions = [];
      _isLoading = true;
    });

    try {
      final details = await _service.getPlaceDetails(
        s.placeId,
        sessionToken: _ensureSessionToken(),
      );
      if (!mounted) return;
      _suppressFetch = true;
      final base = details.fullAddress.isNotEmpty
          ? details.fullAddress
          : s.description;
      widget.controller.text = AddressParser.formatForDisplay(
        base,
        _lastTypedApt,
      );
      setState(() => _isLoading = false);
      widget.onAddressSelected?.call(widget.controller.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _serviceError = _localizedErrorFor(
          e,
          context,
          context.l10n.error_couldNotLoadAddressDetails,
        );
      });
      widget.onAddressSelected?.call(widget.controller.text);
    } finally {
      _sessionToken = null;
      _lastTypedApt = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledTextField(
          label: widget.label ?? context.l10n.common_address,
          controller: widget.controller,
          required: widget.required,
          optional: widget.optional,
          keyboard: TextInputType.streetAddress,
          autofillHints: const [AutofillHints.fullStreetAddress],
          maxLength: TextLimits.appointmentAddress,
          errorText: widget.errorText,
          onChanged: _onTextChanged,
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }
}
