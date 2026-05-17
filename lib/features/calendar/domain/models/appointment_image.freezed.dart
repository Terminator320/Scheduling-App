// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment_image.dart';

T _$identity<T>(T value) => value;
mixin _$AppointmentImage {

 String get url; String get storagePath; String? get fileName; DateTime? get uploadedAt;
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

abstract mixin class $AppointmentImageCopyWith<$Res>  {
  factory $AppointmentImageCopyWith(AppointmentImage value, $Res Function(AppointmentImage) _then) = _$AppointmentImageCopyWithImpl;
@useResult
$Res call({
 String url, String storagePath, String? fileName, DateTime? uploadedAt
});

}
class _$AppointmentImageCopyWithImpl<$Res>
    implements $AppointmentImageCopyWith<$Res> {
  _$AppointmentImageCopyWithImpl(this._self, this._then);

  final AppointmentImage _self;
  final $Res Function(AppointmentImage) _then;

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

extension AppointmentImagePatterns on AppointmentImage {

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppointmentImage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
return $default(_that);case _:
  return orElse();

}
}

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppointmentImage value)  $default,){
final _that = this;
switch (_that) {
case _AppointmentImage():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppointmentImage value)?  $default,){
final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
return $default(_that);case _:
  return null;

}
}

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String storagePath,  String? fileName,  DateTime? uploadedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
return $default(_that.url,_that.storagePath,_that.fileName,_that.uploadedAt);case _:
  return orElse();

}
}

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String storagePath,  String? fileName,  DateTime? uploadedAt)  $default,) {final _that = this;
switch (_that) {
case _AppointmentImage():
return $default(_that.url,_that.storagePath,_that.fileName,_that.uploadedAt);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String storagePath,  String? fileName,  DateTime? uploadedAt)?  $default,) {final _that = this;
switch (_that) {
case _AppointmentImage() when $default != null:
return $default(_that.url,_that.storagePath,_that.fileName,_that.uploadedAt);case _:
  return null;

}
}

}

class _AppointmentImage extends AppointmentImage {
  const _AppointmentImage({this.url = '', this.storagePath = '', this.fileName, this.uploadedAt}): super._();
  
@override@JsonKey() final  String url;
@override@JsonKey() final  String storagePath;
@override final  String? fileName;
@override final  DateTime? uploadedAt;

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

abstract mixin class _$AppointmentImageCopyWith<$Res> implements $AppointmentImageCopyWith<$Res> {
  factory _$AppointmentImageCopyWith(_AppointmentImage value, $Res Function(_AppointmentImage) _then) = __$AppointmentImageCopyWithImpl;
@override @useResult
$Res call({
 String url, String storagePath, String? fileName, DateTime? uploadedAt
});

}
class __$AppointmentImageCopyWithImpl<$Res>
    implements _$AppointmentImageCopyWith<$Res> {
  __$AppointmentImageCopyWithImpl(this._self, this._then);

  final _AppointmentImage _self;
  final $Res Function(_AppointmentImage) _then;

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

