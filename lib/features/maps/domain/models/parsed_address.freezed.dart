// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'parsed_address.dart';

T _$identity<T>(T value) => value;
mixin _$ParsedAddress {

 String get fullAddress; String get street; String get city; String get province; String get postalCode;
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParsedAddressCopyWith<ParsedAddress> get copyWith => _$ParsedAddressCopyWithImpl<ParsedAddress>(this as ParsedAddress, _$identity);

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParsedAddress&&(identical(other.fullAddress, fullAddress) || other.fullAddress == fullAddress)&&(identical(other.street, street) || other.street == street)&&(identical(other.city, city) || other.city == city)&&(identical(other.province, province) || other.province == province)&&(identical(other.postalCode, postalCode) || other.postalCode == postalCode));
}

@override
int get hashCode => Object.hash(runtimeType,fullAddress,street,city,province,postalCode);

@override
String toString() {
  return 'ParsedAddress(fullAddress: $fullAddress, street: $street, city: $city, province: $province, postalCode: $postalCode)';
}

}

abstract mixin class $ParsedAddressCopyWith<$Res>  {
  factory $ParsedAddressCopyWith(ParsedAddress value, $Res Function(ParsedAddress) _then) = _$ParsedAddressCopyWithImpl;
@useResult
$Res call({
 String fullAddress, String street, String city, String province, String postalCode
});

}
class _$ParsedAddressCopyWithImpl<$Res>
    implements $ParsedAddressCopyWith<$Res> {
  _$ParsedAddressCopyWithImpl(this._self, this._then);

  final ParsedAddress _self;
  final $Res Function(ParsedAddress) _then;

@pragma('vm:prefer-inline') @override $Res call({Object? fullAddress = null,Object? street = null,Object? city = null,Object? province = null,Object? postalCode = null,}) {
  return _then(_self.copyWith(
fullAddress: null == fullAddress ? _self.fullAddress : fullAddress // ignore: cast_nullable_to_non_nullable
as String,street: null == street ? _self.street : street // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,province: null == province ? _self.province : province // ignore: cast_nullable_to_non_nullable
as String,postalCode: null == postalCode ? _self.postalCode : postalCode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}

extension ParsedAddressPatterns on ParsedAddress {

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParsedAddress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that);case _:
  return orElse();

}
}

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParsedAddress value)  $default,){
final _that = this;
switch (_that) {
case _ParsedAddress():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParsedAddress value)?  $default,){
final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that);case _:
  return null;

}
}

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String fullAddress,  String street,  String city,  String province,  String postalCode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that.fullAddress,_that.street,_that.city,_that.province,_that.postalCode);case _:
  return orElse();

}
}

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String fullAddress,  String street,  String city,  String province,  String postalCode)  $default,) {final _that = this;
switch (_that) {
case _ParsedAddress():
return $default(_that.fullAddress,_that.street,_that.city,_that.province,_that.postalCode);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String fullAddress,  String street,  String city,  String province,  String postalCode)?  $default,) {final _that = this;
switch (_that) {
case _ParsedAddress() when $default != null:
return $default(_that.fullAddress,_that.street,_that.city,_that.province,_that.postalCode);case _:
  return null;

}
}

}

class _ParsedAddress extends ParsedAddress {
  const _ParsedAddress({this.fullAddress = '', this.street = '', this.city = '', this.province = '', this.postalCode = ''}): super._();
  
@override@JsonKey() final  String fullAddress;
@override@JsonKey() final  String street;
@override@JsonKey() final  String city;
@override@JsonKey() final  String province;
@override@JsonKey() final  String postalCode;

@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParsedAddressCopyWith<_ParsedAddress> get copyWith => __$ParsedAddressCopyWithImpl<_ParsedAddress>(this, _$identity);

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParsedAddress&&(identical(other.fullAddress, fullAddress) || other.fullAddress == fullAddress)&&(identical(other.street, street) || other.street == street)&&(identical(other.city, city) || other.city == city)&&(identical(other.province, province) || other.province == province)&&(identical(other.postalCode, postalCode) || other.postalCode == postalCode));
}

@override
int get hashCode => Object.hash(runtimeType,fullAddress,street,city,province,postalCode);

@override
String toString() {
  return 'ParsedAddress(fullAddress: $fullAddress, street: $street, city: $city, province: $province, postalCode: $postalCode)';
}

}

abstract mixin class _$ParsedAddressCopyWith<$Res> implements $ParsedAddressCopyWith<$Res> {
  factory _$ParsedAddressCopyWith(_ParsedAddress value, $Res Function(_ParsedAddress) _then) = __$ParsedAddressCopyWithImpl;
@override @useResult
$Res call({
 String fullAddress, String street, String city, String province, String postalCode
});

}
class __$ParsedAddressCopyWithImpl<$Res>
    implements _$ParsedAddressCopyWith<$Res> {
  __$ParsedAddressCopyWithImpl(this._self, this._then);

  final _ParsedAddress _self;
  final $Res Function(_ParsedAddress) _then;

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

