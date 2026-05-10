import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/maps/data/google_places_repository.dart';
import 'package:scheduling/features/maps/domain/places_repository.dart';

final placesRepositoryProvider = Provider<PlacesRepository>(
  (ref) => GooglePlacesRepository(),
);
