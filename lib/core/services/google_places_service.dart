import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:scheduling/shared/models/address_suggestion.dart';
import 'package:scheduling/shared/models/parsed_address.dart';

class GooglePlacesService {
  final String _apiKey = dotenv.env['GOOGLE_MAP_API_KEY'] ?? '';


  Future<List<AddressSuggestion>> autocomplete(String input) async {
    if (input.trim().isEmpty) return [];

    if (_apiKey.isEmpty) throw Exception('Google Maps API key is missing');

    final response = await http.post(
      Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
      },
      body: jsonEncode({
        'input': input,
        'includedRegionCodes': ['ca'],
        'locationBias': {
          'circle': {
            'center': {'latitude': 45.5017, 'longitude': -73.5673}, // Montreal
            'radius': 50000.0,
          }
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Autocomplete failed: ${response.body}');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = (data['suggestions'] as List? ?? [])
          .map((e) => AddressSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();

      return suggestions;
    }
    catch (e) {
      throw Exception('Autocomplete failed: ${response.body}');
    }
  }



  Future<ParsedAddress> getPlaceDetails(String placeId) async {
    if (_apiKey.isEmpty) throw Exception('Google Maps API key is missing');

    final response = await http.get(
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
    final components =
    (data['addressComponents'] as List? ?? []).cast<Map<String, dynamic>>();

    String unit = '';
    String streetNumber = '';
    String route = '';
    String city = '';
    String province = '';
    String postalCode = '';

    for (final c in components) {
      final types = (c['types'] as List? ?? []).cast<String>();
      final longText = c['longText'] ?? '';
      final shortText = c['shortText'] ?? '';

      if (types.contains('subpremise')) unit = longText;
      if (types.contains('street_number')) streetNumber = longText;
      if (types.contains('route')) route = longText;
      if (types.contains('locality')) city = longText;
      if (types.contains('administrative_area_level_1')) province = shortText;
      if (types.contains('postal_code')) postalCode = longText;
    }

    final baseStreet = [streetNumber, route]
        .where((e) => e.isNotEmpty)
        .join(' ')
        .trim();

    final street = unit.isNotEmpty && baseStreet.isNotEmpty
        ? '$unit-$baseStreet'
        : baseStreet;

    return ParsedAddress(
      fullAddress: data['formattedAddress'] ?? '',
      street: street,
      city: city,
      province: province,
      postalCode: postalCode,
    );
  }
}