// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment_prefill.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppointmentPrefill {

 ClientRecord? get client;/// True when the job's address was not the client's, so the sheet opens on
/// the address field rather than the client-address pill.
 bool get useCustomAddress;/// Canonical, as stored; the sheet renders the display spelling.
 String get address; String get title; String get notes; String get materialsNeeded;/// Resolved against the live roster by the sheet — only crew still
/// assignable carries over, so a disabled person can't be put on a new job.
 List<String> get employeeIds;/// Seeds the end time when a start is picked (see `setDurationMinutes`);
/// null keeps the form's plain default.
 int? get durationMinutes;
/// Create a copy of AppointmentPrefill
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppointmentPrefillCopyWith<AppointmentPrefill> get copyWith => _$AppointmentPrefillCopyWithImpl<AppointmentPrefill>(this as AppointmentPrefill, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AppointmentPrefill;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppointmentPrefill&&(identical(other.client, _this.client) || other.client == _this.client)&&(identical(other.useCustomAddress, _this.useCustomAddress) || other.useCustomAddress == _this.useCustomAddress)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.materialsNeeded, _this.materialsNeeded) || other.materialsNeeded == _this.materialsNeeded)&&const DeepCollectionEquality().equals(other.employeeIds, _this.employeeIds)&&(identical(other.durationMinutes, _this.durationMinutes) || other.durationMinutes == _this.durationMinutes));
}


@override
int get hashCode {
  final _this = this as AppointmentPrefill;
  return Object.hash(runtimeType,_this.client,_this.useCustomAddress,_this.address,_this.title,_this.notes,_this.materialsNeeded,const DeepCollectionEquality().hash(_this.employeeIds),_this.durationMinutes);
}

@override
String toString() {
  final _this = this as AppointmentPrefill;
  return 'AppointmentPrefill(client: ${_this.client}, useCustomAddress: ${_this.useCustomAddress}, address: ${_this.address}, title: ${_this.title}, notes: ${_this.notes}, materialsNeeded: ${_this.materialsNeeded}, employeeIds: ${_this.employeeIds}, durationMinutes: ${_this.durationMinutes})';
}


}

/// @nodoc
abstract mixin class $AppointmentPrefillCopyWith<$Res>  {
  factory $AppointmentPrefillCopyWith(AppointmentPrefill value, $Res Function(AppointmentPrefill) _then) = _$AppointmentPrefillCopyWithImpl;
@useResult
$Res call({
 ClientRecord? client, bool useCustomAddress, String address, String title, String notes, String materialsNeeded, List<String> employeeIds, int? durationMinutes
});


$ClientRecordCopyWith<$Res>? get client;

}
/// @nodoc
class _$AppointmentPrefillCopyWithImpl<$Res>
    implements $AppointmentPrefillCopyWith<$Res> {
  _$AppointmentPrefillCopyWithImpl(this._self, this._then);

  final AppointmentPrefill _self;
  final $Res Function(AppointmentPrefill) _then;

/// Create a copy of AppointmentPrefill
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? client = freezed,Object? useCustomAddress = null,Object? address = null,Object? title = null,Object? notes = null,Object? materialsNeeded = null,Object? employeeIds = null,Object? durationMinutes = freezed,}) {
  return _then(AppointmentPrefill(
client: freezed == client ? _self.client : client // ignore: cast_nullable_to_non_nullable
as ClientRecord?,useCustomAddress: null == useCustomAddress ? _self.useCustomAddress : useCustomAddress // ignore: cast_nullable_to_non_nullable
as bool,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,materialsNeeded: null == materialsNeeded ? _self.materialsNeeded : materialsNeeded // ignore: cast_nullable_to_non_nullable
as String,employeeIds: null == employeeIds ? _self.employeeIds : employeeIds // ignore: cast_nullable_to_non_nullable
as List<String>,durationMinutes: freezed == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of AppointmentPrefill
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientRecordCopyWith<$Res>? get client {
    if (_self.client == null) {
    return null;
  }

  return $ClientRecordCopyWith<$Res>(_self.client!, (value) {
    return _then(_self.copyWith(client: value));
  });
}
}


/// Adds pattern-matching-related methods to [AppointmentPrefill].
extension AppointmentPrefillPatterns on AppointmentPrefill {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppointmentPrefill value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppointmentPrefill() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppointmentPrefill value)  $default,){
final _that = this;
switch (_that) {
case _AppointmentPrefill():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppointmentPrefill value)?  $default,){
final _that = this;
switch (_that) {
case _AppointmentPrefill() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ClientRecord? client,  bool useCustomAddress,  String address,  String title,  String notes,  String materialsNeeded,  List<String> employeeIds,  int? durationMinutes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppointmentPrefill() when $default != null:
return $default(_that.client,_that.useCustomAddress,_that.address,_that.title,_that.notes,_that.materialsNeeded,_that.employeeIds,_that.durationMinutes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ClientRecord? client,  bool useCustomAddress,  String address,  String title,  String notes,  String materialsNeeded,  List<String> employeeIds,  int? durationMinutes)  $default,) {final _that = this;
switch (_that) {
case _AppointmentPrefill():
return $default(_that.client,_that.useCustomAddress,_that.address,_that.title,_that.notes,_that.materialsNeeded,_that.employeeIds,_that.durationMinutes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ClientRecord? client,  bool useCustomAddress,  String address,  String title,  String notes,  String materialsNeeded,  List<String> employeeIds,  int? durationMinutes)?  $default,) {final _that = this;
switch (_that) {
case _AppointmentPrefill() when $default != null:
return $default(_that.client,_that.useCustomAddress,_that.address,_that.title,_that.notes,_that.materialsNeeded,_that.employeeIds,_that.durationMinutes);case _:
  return null;

}
}

}

/// @nodoc


class _AppointmentPrefill extends AppointmentPrefill {
  const _AppointmentPrefill({this.client, this.useCustomAddress = false, this.address = '', this.title = '', this.notes = '', this.materialsNeeded = '',  List<String> employeeIds = const <String>[], this.durationMinutes}): _employeeIds = employeeIds,super._();
  

@override final  ClientRecord? client;
/// True when the job's address was not the client's, so the sheet opens on
/// the address field rather than the client-address pill.
@override@JsonKey() final  bool useCustomAddress;
/// Canonical, as stored; the sheet renders the display spelling.
@override@JsonKey() final  String address;
@override@JsonKey() final  String title;
@override@JsonKey() final  String notes;
@override@JsonKey() final  String materialsNeeded;
/// Resolved against the live roster by the sheet — only crew still
/// assignable carries over, so a disabled person can't be put on a new job.
 final  List<String> _employeeIds;
/// Resolved against the live roster by the sheet — only crew still
/// assignable carries over, so a disabled person can't be put on a new job.
@override@JsonKey() List<String> get employeeIds {
  if (_employeeIds is EqualUnmodifiableListView) return _employeeIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_employeeIds);
}

/// Seeds the end time when a start is picked (see `setDurationMinutes`);
/// null keeps the form's plain default.
@override final  int? durationMinutes;

/// Create a copy of AppointmentPrefill
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppointmentPrefillCopyWith<_AppointmentPrefill> get copyWith => __$AppointmentPrefillCopyWithImpl<_AppointmentPrefill>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppointmentPrefill&&(identical(other.client, client) || other.client == client)&&(identical(other.useCustomAddress, useCustomAddress) || other.useCustomAddress == useCustomAddress)&&(identical(other.address, address) || other.address == address)&&(identical(other.title, title) || other.title == title)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.materialsNeeded, materialsNeeded) || other.materialsNeeded == materialsNeeded)&&const DeepCollectionEquality().equals(other.employeeIds, _employeeIds)&&(identical(other.durationMinutes, durationMinutes) || other.durationMinutes == durationMinutes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,client,useCustomAddress,address,title,notes,materialsNeeded,const DeepCollectionEquality().hash(_employeeIds),durationMinutes);
}

@override
String toString() {
    return 'AppointmentPrefill(client: $client, useCustomAddress: $useCustomAddress, address: $address, title: $title, notes: $notes, materialsNeeded: $materialsNeeded, employeeIds: $employeeIds, durationMinutes: $durationMinutes)';
}


}

/// @nodoc
abstract mixin class _$AppointmentPrefillCopyWith<$Res> implements $AppointmentPrefillCopyWith<$Res> {
  factory _$AppointmentPrefillCopyWith(_AppointmentPrefill value, $Res Function(_AppointmentPrefill) _then) = __$AppointmentPrefillCopyWithImpl;
@override @useResult
$Res call({
 ClientRecord? client, bool useCustomAddress, String address, String title, String notes, String materialsNeeded, List<String> employeeIds, int? durationMinutes
});


@override $ClientRecordCopyWith<$Res>? get client;

}
/// @nodoc
class __$AppointmentPrefillCopyWithImpl<$Res>
    implements _$AppointmentPrefillCopyWith<$Res> {
  __$AppointmentPrefillCopyWithImpl(this._self, this._then);

  final _AppointmentPrefill _self;
  final $Res Function(_AppointmentPrefill) _then;

/// Create a copy of AppointmentPrefill
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? client = freezed,Object? useCustomAddress = null,Object? address = null,Object? title = null,Object? notes = null,Object? materialsNeeded = null,Object? employeeIds = null,Object? durationMinutes = freezed,}) {
  return _then(_AppointmentPrefill(
client: freezed == client ? _self.client : client // ignore: cast_nullable_to_non_nullable
as ClientRecord?,useCustomAddress: null == useCustomAddress ? _self.useCustomAddress : useCustomAddress // ignore: cast_nullable_to_non_nullable
as bool,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,materialsNeeded: null == materialsNeeded ? _self.materialsNeeded : materialsNeeded // ignore: cast_nullable_to_non_nullable
as String,employeeIds: null == employeeIds ? _self._employeeIds : employeeIds // ignore: cast_nullable_to_non_nullable
as List<String>,durationMinutes: freezed == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of AppointmentPrefill
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientRecordCopyWith<$Res>? get client {
    if (_self.client == null) {
    return null;
  }

  return $ClientRecordCopyWith<$Res>(_self.client!, (value) {
    return _then(_self.copyWith(client: value));
  });
}
}

// dart format on
