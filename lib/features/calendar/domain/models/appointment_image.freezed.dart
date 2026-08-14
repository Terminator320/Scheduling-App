// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment_image.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppointmentImage {

 String get url; String get storagePath;// Round-tripped but never read off an instance: the rendered name comes
// from storagePath. Kept so an existing doc's field survives a rewrite.
 String? get fileName; DateTime? get uploadedAt;
/// Create a copy of AppointmentImage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppointmentImageCopyWith<AppointmentImage> get copyWith => _$AppointmentImageCopyWithImpl<AppointmentImage>(this as AppointmentImage, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppointmentImage&&(identical(other.url, url) || other.url == url)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.uploadedAt, uploadedAt) || other.uploadedAt == uploadedAt));
}


@override
int get hashCode => Object.hash(runtimeType,url,storagePath,fileName,uploadedAt);

@override
String toString() {
  return 'AppointmentImage(url: $url, storagePath: $storagePath, fileName: $fileName, uploadedAt: $uploadedAt)';
}


}

/// @nodoc
abstract mixin class $AppointmentImageCopyWith<$Res>  {
  factory $AppointmentImageCopyWith(AppointmentImage value, $Res Function(AppointmentImage) _then) = _$AppointmentImageCopyWithImpl;
@useResult
$Res call({
 String url, String storagePath, String? fileName, DateTime? uploadedAt
});




}
/// @nodoc
class _$AppointmentImageCopyWithImpl<$Res>
    implements $AppointmentImageCopyWith<$Res> {
  _$AppointmentImageCopyWithImpl(this._self, this._then);

  final AppointmentImage _self;
  final $Res Function(AppointmentImage) _then;

/// Create a copy of AppointmentImage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? storagePath = null,Object? fileName = freezed,Object? uploadedAt = freezed,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,storagePath: null == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,uploadedAt: freezed == uploadedAt ? _self.uploadedAt : uploadedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [AppointmentImage].
extension AppointmentImagePatterns on AppointmentImage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppointmentImage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppointmentImage value)  $default,){
final _that = this;
switch (_that) {
case _AppointmentImage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppointmentImage value)?  $default,){
final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String storagePath,  String? fileName,  DateTime? uploadedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
return $default(_that.url,_that.storagePath,_that.fileName,_that.uploadedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String storagePath,  String? fileName,  DateTime? uploadedAt)  $default,) {final _that = this;
switch (_that) {
case _AppointmentImage():
return $default(_that.url,_that.storagePath,_that.fileName,_that.uploadedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String storagePath,  String? fileName,  DateTime? uploadedAt)?  $default,) {final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
return $default(_that.url,_that.storagePath,_that.fileName,_that.uploadedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AppointmentImage extends AppointmentImage {
  const _AppointmentImage({this.url = '', this.storagePath = '', this.fileName, this.uploadedAt}): super._();
  

@override@JsonKey() final  String url;
@override@JsonKey() final  String storagePath;
// Round-tripped but never read off an instance: the rendered name comes
// from storagePath. Kept so an existing doc's field survives a rewrite.
@override final  String? fileName;
@override final  DateTime? uploadedAt;

/// Create a copy of AppointmentImage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppointmentImageCopyWith<_AppointmentImage> get copyWith => __$AppointmentImageCopyWithImpl<_AppointmentImage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppointmentImage&&(identical(other.url, url) || other.url == url)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.uploadedAt, uploadedAt) || other.uploadedAt == uploadedAt));
}


@override
int get hashCode => Object.hash(runtimeType,url,storagePath,fileName,uploadedAt);

@override
String toString() {
  return 'AppointmentImage(url: $url, storagePath: $storagePath, fileName: $fileName, uploadedAt: $uploadedAt)';
}


}

/// @nodoc
abstract mixin class _$AppointmentImageCopyWith<$Res> implements $AppointmentImageCopyWith<$Res> {
  factory _$AppointmentImageCopyWith(_AppointmentImage value, $Res Function(_AppointmentImage) _then) = __$AppointmentImageCopyWithImpl;
@override @useResult
$Res call({
 String url, String storagePath, String? fileName, DateTime? uploadedAt
});




}
/// @nodoc
class __$AppointmentImageCopyWithImpl<$Res>
    implements _$AppointmentImageCopyWith<$Res> {
  __$AppointmentImageCopyWithImpl(this._self, this._then);

  final _AppointmentImage _self;
  final $Res Function(_AppointmentImage) _then;

/// Create a copy of AppointmentImage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? storagePath = null,Object? fileName = freezed,Object? uploadedAt = freezed,}) {
  return _then(_AppointmentImage(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,storagePath: null == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,uploadedAt: freezed == uploadedAt ? _self.uploadedAt : uploadedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
