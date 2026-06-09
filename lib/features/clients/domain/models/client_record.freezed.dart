// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'client_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ClientContact {

 String get name; String get phone; String get email;
/// Create a copy of ClientContact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientContactCopyWith<ClientContact> get copyWith => _$ClientContactCopyWithImpl<ClientContact>(this as ClientContact, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientContact&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.email, email) || other.email == email));
}


@override
int get hashCode => Object.hash(runtimeType,name,phone,email);

@override
String toString() {
  return 'ClientContact(name: $name, phone: $phone, email: $email)';
}


}

/// @nodoc
abstract mixin class $ClientContactCopyWith<$Res>  {
  factory $ClientContactCopyWith(ClientContact value, $Res Function(ClientContact) _then) = _$ClientContactCopyWithImpl;
@useResult
$Res call({
 String name, String phone, String email
});




}
/// @nodoc
class _$ClientContactCopyWithImpl<$Res>
    implements $ClientContactCopyWith<$Res> {
  _$ClientContactCopyWithImpl(this._self, this._then);

  final ClientContact _self;
  final $Res Function(ClientContact) _then;

/// Create a copy of ClientContact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? phone = null,Object? email = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ClientContact].
extension ClientContactPatterns on ClientContact {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ClientContact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ClientContact() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ClientContact value)  $default,){
final _that = this;
switch (_that) {
case _ClientContact():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ClientContact value)?  $default,){
final _that = this;
switch (_that) {
case _ClientContact() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String phone,  String email)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ClientContact() when $default != null:
return $default(_that.name,_that.phone,_that.email);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String phone,  String email)  $default,) {final _that = this;
switch (_that) {
case _ClientContact():
return $default(_that.name,_that.phone,_that.email);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String phone,  String email)?  $default,) {final _that = this;
switch (_that) {
case _ClientContact() when $default != null:
return $default(_that.name,_that.phone,_that.email);case _:
  return null;

}
}

}

/// @nodoc


class _ClientContact extends ClientContact {
  const _ClientContact({this.name = '', this.phone = '', this.email = ''}): super._();
  

@override@JsonKey() final  String name;
@override@JsonKey() final  String phone;
@override@JsonKey() final  String email;

/// Create a copy of ClientContact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClientContactCopyWith<_ClientContact> get copyWith => __$ClientContactCopyWithImpl<_ClientContact>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClientContact&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.email, email) || other.email == email));
}


@override
int get hashCode => Object.hash(runtimeType,name,phone,email);

@override
String toString() {
  return 'ClientContact(name: $name, phone: $phone, email: $email)';
}


}

/// @nodoc
abstract mixin class _$ClientContactCopyWith<$Res> implements $ClientContactCopyWith<$Res> {
  factory _$ClientContactCopyWith(_ClientContact value, $Res Function(_ClientContact) _then) = __$ClientContactCopyWithImpl;
@override @useResult
$Res call({
 String name, String phone, String email
});




}
/// @nodoc
class __$ClientContactCopyWithImpl<$Res>
    implements _$ClientContactCopyWith<$Res> {
  __$ClientContactCopyWithImpl(this._self, this._then);

  final _ClientContact _self;
  final $Res Function(_ClientContact) _then;

/// Create a copy of ClientContact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? phone = null,Object? email = null,}) {
  return _then(_ClientContact(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ClientRecord {

 String get id; String get businessName; String get name; String get address; String get apt; String get city; String get province; String get country; String get postalCode; String get phone; String get email; List<ClientContact> get contacts; bool get noFixedAddress;
/// Create a copy of ClientRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientRecordCopyWith<ClientRecord> get copyWith => _$ClientRecordCopyWithImpl<ClientRecord>(this as ClientRecord, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.businessName, businessName) || other.businessName == businessName)&&(identical(other.name, name) || other.name == name)&&(identical(other.address, address) || other.address == address)&&(identical(other.apt, apt) || other.apt == apt)&&(identical(other.city, city) || other.city == city)&&(identical(other.province, province) || other.province == province)&&(identical(other.country, country) || other.country == country)&&(identical(other.postalCode, postalCode) || other.postalCode == postalCode)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.email, email) || other.email == email)&&const DeepCollectionEquality().equals(other.contacts, contacts)&&(identical(other.noFixedAddress, noFixedAddress) || other.noFixedAddress == noFixedAddress));
}


@override
int get hashCode => Object.hash(runtimeType,id,businessName,name,address,apt,city,province,country,postalCode,phone,email,const DeepCollectionEquality().hash(contacts),noFixedAddress);

@override
String toString() {
  return 'ClientRecord(id: $id, businessName: $businessName, name: $name, address: $address, apt: $apt, city: $city, province: $province, country: $country, postalCode: $postalCode, phone: $phone, email: $email, contacts: $contacts, noFixedAddress: $noFixedAddress)';
}


}

/// @nodoc
abstract mixin class $ClientRecordCopyWith<$Res>  {
  factory $ClientRecordCopyWith(ClientRecord value, $Res Function(ClientRecord) _then) = _$ClientRecordCopyWithImpl;
@useResult
$Res call({
 String id, String businessName, String name, String address, String apt, String city, String province, String country, String postalCode, String phone, String email, List<ClientContact> contacts, bool noFixedAddress
});




}
/// @nodoc
class _$ClientRecordCopyWithImpl<$Res>
    implements $ClientRecordCopyWith<$Res> {
  _$ClientRecordCopyWithImpl(this._self, this._then);

  final ClientRecord _self;
  final $Res Function(ClientRecord) _then;

/// Create a copy of ClientRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? businessName = null,Object? name = null,Object? address = null,Object? apt = null,Object? city = null,Object? province = null,Object? country = null,Object? postalCode = null,Object? phone = null,Object? email = null,Object? contacts = null,Object? noFixedAddress = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,businessName: null == businessName ? _self.businessName : businessName // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,apt: null == apt ? _self.apt : apt // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,province: null == province ? _self.province : province // ignore: cast_nullable_to_non_nullable
as String,country: null == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String,postalCode: null == postalCode ? _self.postalCode : postalCode // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,contacts: null == contacts ? _self.contacts : contacts // ignore: cast_nullable_to_non_nullable
as List<ClientContact>,noFixedAddress: null == noFixedAddress ? _self.noFixedAddress : noFixedAddress // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ClientRecord].
extension ClientRecordPatterns on ClientRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ClientRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ClientRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ClientRecord value)  $default,){
final _that = this;
switch (_that) {
case _ClientRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ClientRecord value)?  $default,){
final _that = this;
switch (_that) {
case _ClientRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String businessName,  String name,  String address,  String apt,  String city,  String province,  String country,  String postalCode,  String phone,  String email,  List<ClientContact> contacts,  bool noFixedAddress)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ClientRecord() when $default != null:
return $default(_that.id,_that.businessName,_that.name,_that.address,_that.apt,_that.city,_that.province,_that.country,_that.postalCode,_that.phone,_that.email,_that.contacts,_that.noFixedAddress);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String businessName,  String name,  String address,  String apt,  String city,  String province,  String country,  String postalCode,  String phone,  String email,  List<ClientContact> contacts,  bool noFixedAddress)  $default,) {final _that = this;
switch (_that) {
case _ClientRecord():
return $default(_that.id,_that.businessName,_that.name,_that.address,_that.apt,_that.city,_that.province,_that.country,_that.postalCode,_that.phone,_that.email,_that.contacts,_that.noFixedAddress);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String businessName,  String name,  String address,  String apt,  String city,  String province,  String country,  String postalCode,  String phone,  String email,  List<ClientContact> contacts,  bool noFixedAddress)?  $default,) {final _that = this;
switch (_that) {
case _ClientRecord() when $default != null:
return $default(_that.id,_that.businessName,_that.name,_that.address,_that.apt,_that.city,_that.province,_that.country,_that.postalCode,_that.phone,_that.email,_that.contacts,_that.noFixedAddress);case _:
  return null;

}
}

}

/// @nodoc


class _ClientRecord extends ClientRecord {
  const _ClientRecord({required this.id, this.businessName = '', this.name = '', this.address = '', this.apt = '', this.city = '', this.province = '', this.country = '', this.postalCode = '', this.phone = '', this.email = '', final  List<ClientContact> contacts = const <ClientContact>[], this.noFixedAddress = false}): _contacts = contacts,super._();
  

@override final  String id;
@override@JsonKey() final  String businessName;
@override@JsonKey() final  String name;
@override@JsonKey() final  String address;
@override@JsonKey() final  String apt;
@override@JsonKey() final  String city;
@override@JsonKey() final  String province;
@override@JsonKey() final  String country;
@override@JsonKey() final  String postalCode;
@override@JsonKey() final  String phone;
@override@JsonKey() final  String email;
 final  List<ClientContact> _contacts;
@override@JsonKey() List<ClientContact> get contacts {
  if (_contacts is EqualUnmodifiableListView) return _contacts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_contacts);
}

@override@JsonKey() final  bool noFixedAddress;

/// Create a copy of ClientRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClientRecordCopyWith<_ClientRecord> get copyWith => __$ClientRecordCopyWithImpl<_ClientRecord>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClientRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.businessName, businessName) || other.businessName == businessName)&&(identical(other.name, name) || other.name == name)&&(identical(other.address, address) || other.address == address)&&(identical(other.apt, apt) || other.apt == apt)&&(identical(other.city, city) || other.city == city)&&(identical(other.province, province) || other.province == province)&&(identical(other.country, country) || other.country == country)&&(identical(other.postalCode, postalCode) || other.postalCode == postalCode)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.email, email) || other.email == email)&&const DeepCollectionEquality().equals(other._contacts, _contacts)&&(identical(other.noFixedAddress, noFixedAddress) || other.noFixedAddress == noFixedAddress));
}


@override
int get hashCode => Object.hash(runtimeType,id,businessName,name,address,apt,city,province,country,postalCode,phone,email,const DeepCollectionEquality().hash(_contacts),noFixedAddress);

@override
String toString() {
  return 'ClientRecord(id: $id, businessName: $businessName, name: $name, address: $address, apt: $apt, city: $city, province: $province, country: $country, postalCode: $postalCode, phone: $phone, email: $email, contacts: $contacts, noFixedAddress: $noFixedAddress)';
}


}

/// @nodoc
abstract mixin class _$ClientRecordCopyWith<$Res> implements $ClientRecordCopyWith<$Res> {
  factory _$ClientRecordCopyWith(_ClientRecord value, $Res Function(_ClientRecord) _then) = __$ClientRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String businessName, String name, String address, String apt, String city, String province, String country, String postalCode, String phone, String email, List<ClientContact> contacts, bool noFixedAddress
});




}
/// @nodoc
class __$ClientRecordCopyWithImpl<$Res>
    implements _$ClientRecordCopyWith<$Res> {
  __$ClientRecordCopyWithImpl(this._self, this._then);

  final _ClientRecord _self;
  final $Res Function(_ClientRecord) _then;

/// Create a copy of ClientRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? businessName = null,Object? name = null,Object? address = null,Object? apt = null,Object? city = null,Object? province = null,Object? country = null,Object? postalCode = null,Object? phone = null,Object? email = null,Object? contacts = null,Object? noFixedAddress = null,}) {
  return _then(_ClientRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,businessName: null == businessName ? _self.businessName : businessName // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,apt: null == apt ? _self.apt : apt // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,province: null == province ? _self.province : province // ignore: cast_nullable_to_non_nullable
as String,country: null == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String,postalCode: null == postalCode ? _self.postalCode : postalCode // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,contacts: null == contacts ? _self._contacts : contacts // ignore: cast_nullable_to_non_nullable
as List<ClientContact>,noFixedAddress: null == noFixedAddress ? _self.noFixedAddress : noFixedAddress // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
