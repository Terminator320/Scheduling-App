// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'address_suggestion.dart';

T _$identity<T>(T value) => value;
mixin _$AddressSuggestion {

 String get placeId; String get description;
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddressSuggestionCopyWith<AddressSuggestion> get copyWith => _$AddressSuggestionCopyWithImpl<AddressSuggestion>(this as AddressSuggestion, _$identity);

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddressSuggestion&&(identical(other.placeId, placeId) || other.placeId == placeId)&&(identical(other.description, description) || other.description == description));
}

@override
int get hashCode => Object.hash(runtimeType,placeId,description);

@override
String toString() {
  return 'AddressSuggestion(placeId: $placeId, description: $description)';
}

}

abstract mixin class $AddressSuggestionCopyWith<$Res>  {
  factory $AddressSuggestionCopyWith(AddressSuggestion value, $Res Function(AddressSuggestion) _then) = _$AddressSuggestionCopyWithImpl;
@useResult
$Res call({
 String placeId, String description
});

}
class _$AddressSuggestionCopyWithImpl<$Res>
    implements $AddressSuggestionCopyWith<$Res> {
  _$AddressSuggestionCopyWithImpl(this._self, this._then);

  final AddressSuggestion _self;
  final $Res Function(AddressSuggestion) _then;

@pragma('vm:prefer-inline') @override $Res call({Object? placeId = null,Object? description = null,}) {
  return _then(_self.copyWith(
placeId: null == placeId ? _self.placeId : placeId // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}

extension AddressSuggestionPatterns on AddressSuggestion {

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AddressSuggestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
return $default(_that);case _:
  return orElse();

}
}

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AddressSuggestion value)  $default,){
final _that = this;
switch (_that) {
case _AddressSuggestion():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AddressSuggestion value)?  $default,){
final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
return $default(_that);case _:
  return null;

}
}

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String placeId,  String description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
return $default(_that.placeId,_that.description);case _:
  return orElse();

}
}

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String placeId,  String description)  $default,) {final _that = this;
switch (_that) {
case _AddressSuggestion():
return $default(_that.placeId,_that.description);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String placeId,  String description)?  $default,) {final _that = this;
switch (_that) {
case _AddressSuggestion() when $default != null:
return $default(_that.placeId,_that.description);case _:
  return null;

}
}

}

class _AddressSuggestion extends AddressSuggestion {
  const _AddressSuggestion({this.placeId = '', this.description = ''}): super._();
  
@override@JsonKey() final  String placeId;
@override@JsonKey() final  String description;

@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddressSuggestionCopyWith<_AddressSuggestion> get copyWith => __$AddressSuggestionCopyWithImpl<_AddressSuggestion>(this, _$identity);

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AddressSuggestion&&(identical(other.placeId, placeId) || other.placeId == placeId)&&(identical(other.description, description) || other.description == description));
}

@override
int get hashCode => Object.hash(runtimeType,placeId,description);

@override
String toString() {
  return 'AddressSuggestion(placeId: $placeId, description: $description)';
}

}

abstract mixin class _$AddressSuggestionCopyWith<$Res> implements $AddressSuggestionCopyWith<$Res> {
  factory _$AddressSuggestionCopyWith(_AddressSuggestion value, $Res Function(_AddressSuggestion) _then) = __$AddressSuggestionCopyWithImpl;
@override @useResult
$Res call({
 String placeId, String description
});

}
class __$AddressSuggestionCopyWithImpl<$Res>
    implements _$AddressSuggestionCopyWith<$Res> {
  __$AddressSuggestionCopyWithImpl(this._self, this._then);

  final _AddressSuggestion _self;
  final $Res Function(_AddressSuggestion) _then;

@override @pragma('vm:prefer-inline') $Res call({Object? placeId = null,Object? description = null,}) {
  return _then(_AddressSuggestion(
placeId: null == placeId ? _self.placeId : placeId // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}

