// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'field_note.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FieldNote {

 String get id; String get text; String get authorId; String get authorName; DateTime? get createdAt;
/// Create a copy of FieldNote
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldNoteCopyWith<FieldNote> get copyWith => _$FieldNoteCopyWithImpl<FieldNote>(this as FieldNote, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FieldNote;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldNote&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.authorId, _this.authorId) || other.authorId == _this.authorId)&&(identical(other.authorName, _this.authorName) || other.authorName == _this.authorName)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as FieldNote;
  return Object.hash(runtimeType,_this.id,_this.text,_this.authorId,_this.authorName,_this.createdAt);
}

@override
String toString() {
  final _this = this as FieldNote;
  return 'FieldNote(id: ${_this.id}, text: ${_this.text}, authorId: ${_this.authorId}, authorName: ${_this.authorName}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $FieldNoteCopyWith<$Res>  {
  factory $FieldNoteCopyWith(FieldNote value, $Res Function(FieldNote) _then) = _$FieldNoteCopyWithImpl;
@useResult
$Res call({
 String id, String text, String authorId, String authorName, DateTime? createdAt
});




}
/// @nodoc
class _$FieldNoteCopyWithImpl<$Res>
    implements $FieldNoteCopyWith<$Res> {
  _$FieldNoteCopyWithImpl(this._self, this._then);

  final FieldNote _self;
  final $Res Function(FieldNote) _then;

/// Create a copy of FieldNote
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? text = null,Object? authorId = null,Object? authorName = null,Object? createdAt = freezed,}) {
  return _then(FieldNote(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,authorId: null == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String,authorName: null == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [FieldNote].
extension FieldNotePatterns on FieldNote {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FieldNote value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FieldNote() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FieldNote value)  $default,){
final _that = this;
switch (_that) {
case _FieldNote():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FieldNote value)?  $default,){
final _that = this;
switch (_that) {
case _FieldNote() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String text,  String authorId,  String authorName,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FieldNote() when $default != null:
return $default(_that.id,_that.text,_that.authorId,_that.authorName,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String text,  String authorId,  String authorName,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _FieldNote():
return $default(_that.id,_that.text,_that.authorId,_that.authorName,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String text,  String authorId,  String authorName,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _FieldNote() when $default != null:
return $default(_that.id,_that.text,_that.authorId,_that.authorName,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _FieldNote extends FieldNote {
  const _FieldNote({required this.id, this.text = '', this.authorId = '', this.authorName = '', this.createdAt}): super._();
  

@override final  String id;
@override@JsonKey() final  String text;
@override@JsonKey() final  String authorId;
@override@JsonKey() final  String authorName;
@override final  DateTime? createdAt;

/// Create a copy of FieldNote
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FieldNoteCopyWith<_FieldNote> get copyWith => __$FieldNoteCopyWithImpl<_FieldNote>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FieldNote&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.authorName, authorName) || other.authorName == authorName)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,text,authorId,authorName,createdAt);
}

@override
String toString() {
    return 'FieldNote(id: $id, text: $text, authorId: $authorId, authorName: $authorName, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$FieldNoteCopyWith<$Res> implements $FieldNoteCopyWith<$Res> {
  factory _$FieldNoteCopyWith(_FieldNote value, $Res Function(_FieldNote) _then) = __$FieldNoteCopyWithImpl;
@override @useResult
$Res call({
 String id, String text, String authorId, String authorName, DateTime? createdAt
});




}
/// @nodoc
class __$FieldNoteCopyWithImpl<$Res>
    implements _$FieldNoteCopyWith<$Res> {
  __$FieldNoteCopyWithImpl(this._self, this._then);

  final _FieldNote _self;
  final $Res Function(_FieldNote) _then;

/// Create a copy of FieldNote
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,Object? authorId = null,Object? authorName = null,Object? createdAt = freezed,}) {
  return _then(_FieldNote(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,authorId: null == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String,authorName: null == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
