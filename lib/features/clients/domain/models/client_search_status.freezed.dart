// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'client_search_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ClientSearchStatus {

 ClientQueryMode get mode; int get digitsTyped; bool get failed; PhoneRung? get answeredRung;
/// Create a copy of ClientSearchStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientSearchStatusCopyWith<ClientSearchStatus> get copyWith => _$ClientSearchStatusCopyWithImpl<ClientSearchStatus>(this as ClientSearchStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ClientSearchStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientSearchStatus&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.digitsTyped, _this.digitsTyped) || other.digitsTyped == _this.digitsTyped)&&(identical(other.failed, _this.failed) || other.failed == _this.failed)&&(identical(other.answeredRung, _this.answeredRung) || other.answeredRung == _this.answeredRung));
}


@override
int get hashCode {
  final _this = this as ClientSearchStatus;
  return Object.hash(runtimeType,_this.mode,_this.digitsTyped,_this.failed,_this.answeredRung);
}

@override
String toString() {
  final _this = this as ClientSearchStatus;
  return 'ClientSearchStatus(mode: ${_this.mode}, digitsTyped: ${_this.digitsTyped}, failed: ${_this.failed}, answeredRung: ${_this.answeredRung})';
}


}

/// @nodoc
abstract mixin class $ClientSearchStatusCopyWith<$Res>  {
  factory $ClientSearchStatusCopyWith(ClientSearchStatus value, $Res Function(ClientSearchStatus) _then) = _$ClientSearchStatusCopyWithImpl;
@useResult
$Res call({
 ClientQueryMode mode, int digitsTyped, bool failed, PhoneRung? answeredRung
});




}
/// @nodoc
class _$ClientSearchStatusCopyWithImpl<$Res>
    implements $ClientSearchStatusCopyWith<$Res> {
  _$ClientSearchStatusCopyWithImpl(this._self, this._then);

  final ClientSearchStatus _self;
  final $Res Function(ClientSearchStatus) _then;

/// Create a copy of ClientSearchStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? digitsTyped = null,Object? failed = null,Object? answeredRung = freezed,}) {
  return _then(ClientSearchStatus(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ClientQueryMode,digitsTyped: null == digitsTyped ? _self.digitsTyped : digitsTyped // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as bool,answeredRung: freezed == answeredRung ? _self.answeredRung : answeredRung // ignore: cast_nullable_to_non_nullable
as PhoneRung?,
  ));
}

}


/// Adds pattern-matching-related methods to [ClientSearchStatus].
extension ClientSearchStatusPatterns on ClientSearchStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ClientSearchStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ClientSearchStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ClientSearchStatus value)  $default,){
final _that = this;
switch (_that) {
case _ClientSearchStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ClientSearchStatus value)?  $default,){
final _that = this;
switch (_that) {
case _ClientSearchStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ClientQueryMode mode,  int digitsTyped,  bool failed,  PhoneRung? answeredRung)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ClientSearchStatus() when $default != null:
return $default(_that.mode,_that.digitsTyped,_that.failed,_that.answeredRung);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ClientQueryMode mode,  int digitsTyped,  bool failed,  PhoneRung? answeredRung)  $default,) {final _that = this;
switch (_that) {
case _ClientSearchStatus():
return $default(_that.mode,_that.digitsTyped,_that.failed,_that.answeredRung);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ClientQueryMode mode,  int digitsTyped,  bool failed,  PhoneRung? answeredRung)?  $default,) {final _that = this;
switch (_that) {
case _ClientSearchStatus() when $default != null:
return $default(_that.mode,_that.digitsTyped,_that.failed,_that.answeredRung);case _:
  return null;

}
}

}

/// @nodoc


class _ClientSearchStatus extends ClientSearchStatus {
  const _ClientSearchStatus({this.mode = ClientQueryMode.phone, this.digitsTyped = 0, this.failed = false, this.answeredRung}): super._();
  

@override@JsonKey() final  ClientQueryMode mode;
@override@JsonKey() final  int digitsTyped;
@override@JsonKey() final  bool failed;
@override final  PhoneRung? answeredRung;

/// Create a copy of ClientSearchStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClientSearchStatusCopyWith<_ClientSearchStatus> get copyWith => __$ClientSearchStatusCopyWithImpl<_ClientSearchStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClientSearchStatus&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.digitsTyped, digitsTyped) || other.digitsTyped == digitsTyped)&&(identical(other.failed, failed) || other.failed == failed)&&(identical(other.answeredRung, answeredRung) || other.answeredRung == answeredRung));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mode,digitsTyped,failed,answeredRung);
}

@override
String toString() {
    return 'ClientSearchStatus(mode: $mode, digitsTyped: $digitsTyped, failed: $failed, answeredRung: $answeredRung)';
}


}

/// @nodoc
abstract mixin class _$ClientSearchStatusCopyWith<$Res> implements $ClientSearchStatusCopyWith<$Res> {
  factory _$ClientSearchStatusCopyWith(_ClientSearchStatus value, $Res Function(_ClientSearchStatus) _then) = __$ClientSearchStatusCopyWithImpl;
@override @useResult
$Res call({
 ClientQueryMode mode, int digitsTyped, bool failed, PhoneRung? answeredRung
});




}
/// @nodoc
class __$ClientSearchStatusCopyWithImpl<$Res>
    implements _$ClientSearchStatusCopyWith<$Res> {
  __$ClientSearchStatusCopyWithImpl(this._self, this._then);

  final _ClientSearchStatus _self;
  final $Res Function(_ClientSearchStatus) _then;

/// Create a copy of ClientSearchStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? digitsTyped = null,Object? failed = null,Object? answeredRung = freezed,}) {
  return _then(_ClientSearchStatus(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ClientQueryMode,digitsTyped: null == digitsTyped ? _self.digitsTyped : digitsTyped // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as bool,answeredRung: freezed == answeredRung ? _self.answeredRung : answeredRung // ignore: cast_nullable_to_non_nullable
as PhoneRung?,
  ));
}


}

// dart format on
