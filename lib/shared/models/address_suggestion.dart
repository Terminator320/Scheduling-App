class AddressSuggestion {
  final String placeId;
  final String description;

  AddressSuggestion({
    required this.placeId,
    required this.description,
  });

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final placePrediction =
        json['placePrediction'] as Map<String, dynamic>? ?? {};

    return AddressSuggestion(
      placeId: placePrediction['placeId'] ?? '',
      description: placePrediction['text']?['text'] ?? '',
    );
  }
}