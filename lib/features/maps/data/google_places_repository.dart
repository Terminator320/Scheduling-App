import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'package:scheduling/features/maps/domain/models/address_suggestion.dart';
import 'package:scheduling/features/maps/domain/models/parsed_address.dart';
import 'package:scheduling/features/maps/domain/places_repository.dart';

class GooglePlacesRepository implements PlacesRepository {
  GooglePlacesRepository({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? (dotenv.env['GOOGLE_MAP_API_KEY'] ?? '');

  final http.Client _client;
  final String _apiKey;

  static final _autocompleteUri = Uri.parse(
    'https://places.googleapis.com/v1/places:autocomplete',
  );

  @override
  Future<List<AddressSuggestion>> autocomplete(String input) async {
    if (input.trim().isEmpty) return const [];
    if (_apiKey.isEmpty) throw Exception('Google Maps API key is missing');

    final response = await _client.post(
      _autocompleteUri,
      headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': _apiKey},
      body: jsonEncode({
        'input': input,
        'includedRegionCodes': ['ca'],
        'locationBias': {
          'circle': {
            'center': {'latitude': 45.5017, 'longitude': -73.5673}, // Montreal
            'radius': 50000.0,
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Autocomplete failed: ${response.body}');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['suggestions'] as List? ?? [])
          .map((e) => AddressSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException catch (e) {
      // Don't echo `response.body` back into the exception message — it can
      // include API noise and balloons logs. The original FormatException
      // carries the position info already.
      throw Exception('Autocomplete response was not valid JSON: $e');
    }
  }

  @override
  Future<ParsedAddress> getPlaceDetails(String placeId) async {
    if (_apiKey.isEmpty) throw Exception('Google Maps API key is missing');

    final response = await _client.get(
      Uri.parse('https://places.googleapis.com/v1/places/$placeId'),
      headers: {
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask': 'formattedAddress,addressComponents',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Place details failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final components = (data['addressComponents'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    var unit = '';
    var streetNumber = '';
    var route = '';
    var city = '';
    var province = '';
    var postalCode = '';

    for (final c in components) {
      final types = (c['types'] as List? ?? []).cast<String>();
      final longText = (c['longText'] as String?) ?? '';
      final shortText = (c['shortText'] as String?) ?? '';

      if (types.contains('subpremise')) unit = longText;
      if (types.contains('street_number')) streetNumber = longText;
      if (types.contains('route')) route = longText;
      if (types.contains('locality')) city = longText;
      if (types.contains('administrative_area_level_1')) province = shortText;
      if (types.contains('postal_code')) postalCode = longText;
    }

    final baseStreet = [
      streetNumber,
      route,
    ].where((e) => e.isNotEmpty).join(' ').trim();

    final street = unit.isNotEmpty && baseStreet.isNotEmpty
        ? '$unit-$baseStreet'
        : baseStreet;

    return ParsedAddress(
      fullAddress: (data['formattedAddress'] as String?) ?? '',
      street: street,
      city: city,
      province: province,
      postalCode: postalCode,
    );
  }
}
