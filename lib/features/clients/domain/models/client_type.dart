import 'package:scheduling/l10n/l10n.dart';

/// What kind of customer this is. Stored as [raw]; an empty string means the
/// admin never picked one, which is a normal state and not an error.
enum ClientType {
  unset(''),
  residential('residential'),
  commercial('commercial'),
  propertyManagement('property_mgmt');

  const ClientType(this.raw);

  /// The value stored on the Firestore doc.
  final String raw;

  /// Unknown and legacy values fall back to [unset] — mirrors `UserStatus.fromRaw`.
  static ClientType fromRaw(String? value) {
    final trimmed = (value ?? '').trim();
    for (final type in ClientType.values) {
      if (type.raw == trimmed) return type;
    }
    return ClientType.unset;
  }

  /// The three pickable types, in the order the chips render.
  static const List<ClientType> pickable = [
    ClientType.residential,
    ClientType.commercial,
    ClientType.propertyManagement,
  ];
}

/// Localized chip label (mirrors `jobTemplateLabel`).
String clientTypeLabel(AppLocalizations l10n, ClientType type) =>
    switch (type) {
      ClientType.unset => '',
      ClientType.residential => l10n.clients_typeResidential,
      ClientType.commercial => l10n.clients_typeCommercial,
      ClientType.propertyManagement => l10n.clients_typePropertyManagement,
    };
