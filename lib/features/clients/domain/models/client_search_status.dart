import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scheduling/features/clients/domain/policies/phone_query_policy.dart';

part 'client_search_status.freezed.dart';

/// Which keyboard and which matcher the client field is using.
enum ClientQueryMode { phone, text }

/// Everything the picker renders about the current search EXCEPT the results
/// themselves, which stay on `clientResults` so the existing state contract and
/// its tests are untouched.
@freezed
abstract class ClientSearchStatus with _$ClientSearchStatus {
  const factory ClientSearchStatus({
    @Default(ClientQueryMode.phone) ClientQueryMode mode,
    @Default(0) int digitsTyped,
    @Default(false) bool failed,
    PhoneRung? answeredRung,
  }) = _ClientSearchStatus;

  const ClientSearchStatus._();

  /// Digits typed, but not yet enough to send. The picker shows pips, not rows.
  bool get isHolding =>
      mode == ClientQueryMode.phone &&
      digitsTyped > 0 &&
      digitsTyped < PhoneQueryPolicy.minPhoneDigits;

  /// The answer came from a fallback rung, so these are near misses and must be
  /// labelled "closest numbers on file" rather than presented as matches.
  bool get isFallback =>
      answeredRung != null && answeredRung != PhoneRung.canonical;
}
