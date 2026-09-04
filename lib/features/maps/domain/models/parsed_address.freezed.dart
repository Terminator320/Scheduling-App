// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'parsed_address.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ParsedAddress {

 String get fullAddress; String get street; String get city; String get province; String get postalCode;
/// Create a copy of ParsedAddress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParsedAddressCopyWith<ParsedAddress> get copyWith => _$ParsedAddressCopyWithImpl<ParsedAddress>(this as ParsedAddress, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ParsedAddress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParsedAddress&&(identical(other.fullAddress, _this.fullAddress) || other.fullAddress == _this.fullAddress)&&(identical(other.street, _this.street) || other.street == _this.street)&&(identical(other.city, _this.city) || other.city == _this.city)&&(identical(other.province, _this.province) || other.province == _this.province)&&(identical(other.postalCode, _this.postalCode) || other.postalCode == _this.postalCode));
}


@override
int get hashCode {
  final _this = this as ParsedAddress;
  return Object.hash(runtimeType,_this.fullAddress,_this.street,_this.city,_this.province,_this.postalCode);
}

@override
String toString() {
  final _this = this as ParsedAddress;
  return 'ParsedAddress(fullAddress: ${_this.fullAddress}, street: ${_this.street}, city: ${_this.city}, province: ${_this.province}, postalCode: ${_this.postalCode})';
}


}

/// @nodoc
abstract mixin class $ParsedAddressCopyWith<$Res>  {
  factory $ParsedAddressCopyWith(ParsedAddress value, $Res Function(ParsedAddress) _then) = _$ParsedAddressCopyWithImpl;
@useResult
$Res call({
 String fullAddress, String street, String city, String province, String postalCode
});




}
/// @nodoc
class _$ParsedAddressCopyWithImpl<$Res>
    implements $ParsedAddressCopyWith<$Res> {
  _$ParsedAddressCopyWithImpl(this._self, this._then);

  final ParsedAddress _self;
  final $Res Function(ParsedAddress) _then;

/// Create a copy of ParsedAddress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fullAddress = null,Object? street = null,Object? city = null,Object? province = null,Object? postalCode = null,}) {
  return _then(ParsedAddress(
fullAddress: null == fullAddress ? _self.fullAddress : fullAddress // ignore: cast_nullable_to_non_nullable
as String,street: null == street ? _self.street : street // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,province: null == province ? _self.province : province // ignore: cast_nullable_to_non_nullable
as String,postalCode: null == postalCode ? _self.postalCode : postalCode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ParsedAddress].
extension ParsedAddressPatterns on ParsedAddress {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParsedAddress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParsedAddress value)  $default,){
final _that = this;
switch (_that) {
case _ParsedAddress():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParsedAddress value)?  $default,){
final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String fullAddress,  String street,  String city,  String province,  String postalCode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that.fullAddress,_that.street,_that.city,_that.province,_that.postalCode);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String fullAddress,  String street,  String city,  String province,  String postalCode)  $default,) {final _that = this;
switch (_that) {
case _ParsedAddress():
return $default(_that.fullAddress,_that.street,_that.city,_that.province,_that.postalCode);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String fullAddress,  String street,  String city,  String province,  String postalCode)?  $default,) {final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that.fullAddress,_that.street,_that.city,_that.province,_that.postalCode);case _:
  return null;

}
}

}

/// @nodoc


class _ParsedAddress extends ParsedAddress {
  const _ParsedAddress({this.fullAddress = '', this.street = '', this.city = '', this.province = '', this.postalCode = ''}): super._();
  

@override@JsonKey() final  String fullAddress;
@override@JsonKey() final  String street;
@override@JsonKey() final  String city;
@override@JsonKey() final  String province;
@override@JsonKey() final  String postalCode;

/// Create a copy of ParsedAddress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParsedAddressCopyWith<_ParsedAddress> get copyWith => __$ParsedAddressCopyWithImpl<_ParsedAddress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParsedAddress&&(identical(other.fullAddress, fullAddress) || other.fullAddress == fullAddress)&&(identical(other.street, street) || other.street == street)&&(identical(other.city, city) || other.city == city)&&(identical(other.province, province) || other.province == province)&&(identical(other.postalCode, postalCode) || other.postalCode == postalCode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fullAddress,street,city,province,postalCode);
}

@override
String toString() {
    return 'ParsedAddress(fullAddress: $fullAddress, street: $street, city: $city, province: $province, postalCode: $postalCode)';
}


}

/// @nodoc
abstract mixin class _$ParsedAddressCopyWith<$Res> implements $ParsedAddressCopyWith<$Res> {
  factory _$ParsedAddressCopyWith(_ParsedAddress value, $Res Function(_ParsedAddress) _then) = __$ParsedAddressCopyWithImpl;
@override @useResult
$Res call({
 String fullAddress, String street, String city, String province, String postalCode
});




}
/// @nodoc
class __$ParsedAddressCopyWithImpl<$Res>
    implements _$ParsedAddressCopyWith<$Res> {
  __$ParsedAddressCopyWithImpl(this._self, this._then);

  final _ParsedAddress _self;
  final $Res Function(_ParsedAddress) _then;

/// Create a copy of ParsedAddress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fullAddress = null,Object? street = null,Object? city = null,Object? province = null,Object? postalCode = null,}) {
  return _then(_ParsedAddress(
fullAddress: null == fullAddress ? _self.fullAddress : fullAddress // ignore: cast_nullable_to_non_nullable
as String,street: null == street ? _self.street : street // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,province: null == province ? _self.province : province // ignore: cast_nullable_to_non_nullable
as String,postalCode: null == postalCode ? _self.postalCode : postalCode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
