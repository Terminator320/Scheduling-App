// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppointmentRecord {

 DateTime get startTime; DateTime get endTime; String? get id; String get title; String get clientId; String get clientName; String get clientPhone; List<String> get employeeIds; List<String> get employeeNames; String get address; String get notes; String get fieldNotes; String get materialsNeeded; String get status; bool get isPersonal; bool get isAllDay; bool get isDayOff; RepeatInterval get repeat; String get seriesId; int get dayIndex; int get dayCount; DateTime? get createdAt; DateTime? get updatedAt; int get pictureCount; DateTime? get startedAt; DateTime? get completedAt;
/// Create a copy of AppointmentRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppointmentRecordCopyWith<AppointmentRecord> get copyWith => _$AppointmentRecordCopyWithImpl<AppointmentRecord>(this as AppointmentRecord, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AppointmentRecord;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppointmentRecord&&(identical(other.startTime, _this.startTime) || other.startTime == _this.startTime)&&(identical(other.endTime, _this.endTime) || other.endTime == _this.endTime)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.clientId, _this.clientId) || other.clientId == _this.clientId)&&(identical(other.clientName, _this.clientName) || other.clientName == _this.clientName)&&(identical(other.clientPhone, _this.clientPhone) || other.clientPhone == _this.clientPhone)&&const DeepCollectionEquality().equals(other.employeeIds, _this.employeeIds)&&const DeepCollectionEquality().equals(other.employeeNames, _this.employeeNames)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.fieldNotes, _this.fieldNotes) || other.fieldNotes == _this.fieldNotes)&&(identical(other.materialsNeeded, _this.materialsNeeded) || other.materialsNeeded == _this.materialsNeeded)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.isPersonal, _this.isPersonal) || other.isPersonal == _this.isPersonal)&&(identical(other.isAllDay, _this.isAllDay) || other.isAllDay == _this.isAllDay)&&(identical(other.isDayOff, _this.isDayOff) || other.isDayOff == _this.isDayOff)&&(identical(other.repeat, _this.repeat) || other.repeat == _this.repeat)&&(identical(other.seriesId, _this.seriesId) || other.seriesId == _this.seriesId)&&(identical(other.dayIndex, _this.dayIndex) || other.dayIndex == _this.dayIndex)&&(identical(other.dayCount, _this.dayCount) || other.dayCount == _this.dayCount)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.pictureCount, _this.pictureCount) || other.pictureCount == _this.pictureCount)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.completedAt, _this.completedAt) || other.completedAt == _this.completedAt));
}


@override
int get hashCode {
  final _this = this as AppointmentRecord;
  return Object.hashAll([runtimeType,_this.startTime,_this.endTime,_this.id,_this.title,_this.clientId,_this.clientName,_this.clientPhone,const DeepCollectionEquality().hash(_this.employeeIds),const DeepCollectionEquality().hash(_this.employeeNames),_this.address,_this.notes,_this.fieldNotes,_this.materialsNeeded,_this.status,_this.isPersonal,_this.isAllDay,_this.isDayOff,_this.repeat,_this.seriesId,_this.dayIndex,_this.dayCount,_this.createdAt,_this.updatedAt,_this.pictureCount,_this.startedAt,_this.completedAt]);
}

@override
String toString() {
  final _this = this as AppointmentRecord;
  return 'AppointmentRecord(startTime: ${_this.startTime}, endTime: ${_this.endTime}, id: ${_this.id}, title: ${_this.title}, clientId: ${_this.clientId}, clientName: ${_this.clientName}, clientPhone: ${_this.clientPhone}, employeeIds: ${_this.employeeIds}, employeeNames: ${_this.employeeNames}, address: ${_this.address}, notes: ${_this.notes}, fieldNotes: ${_this.fieldNotes}, materialsNeeded: ${_this.materialsNeeded}, status: ${_this.status}, isPersonal: ${_this.isPersonal}, isAllDay: ${_this.isAllDay}, isDayOff: ${_this.isDayOff}, repeat: ${_this.repeat}, seriesId: ${_this.seriesId}, dayIndex: ${_this.dayIndex}, dayCount: ${_this.dayCount}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, pictureCount: ${_this.pictureCount}, startedAt: ${_this.startedAt}, completedAt: ${_this.completedAt})';
}


}

/// @nodoc
abstract mixin class $AppointmentRecordCopyWith<$Res>  {
  factory $AppointmentRecordCopyWith(AppointmentRecord value, $Res Function(AppointmentRecord) _then) = _$AppointmentRecordCopyWithImpl;
@useResult
$Res call({
 DateTime startTime, DateTime endTime, String? id, String title, String clientId, String clientName, String clientPhone, List<String> employeeIds, List<String> employeeNames, String address, String notes, String fieldNotes, String materialsNeeded, String status, bool isPersonal, bool isAllDay, bool isDayOff, RepeatInterval repeat, String seriesId, int dayIndex, int dayCount, DateTime? createdAt, DateTime? updatedAt, int pictureCount, DateTime? startedAt, DateTime? completedAt
});




}
/// @nodoc
class _$AppointmentRecordCopyWithImpl<$Res>
    implements $AppointmentRecordCopyWith<$Res> {
  _$AppointmentRecordCopyWithImpl(this._self, this._then);

  final AppointmentRecord _self;
  final $Res Function(AppointmentRecord) _then;

/// Create a copy of AppointmentRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? startTime = null,Object? endTime = null,Object? id = freezed,Object? title = null,Object? clientId = null,Object? clientName = null,Object? clientPhone = null,Object? employeeIds = null,Object? employeeNames = null,Object? address = null,Object? notes = null,Object? fieldNotes = null,Object? materialsNeeded = null,Object? status = null,Object? isPersonal = null,Object? isAllDay = null,Object? isDayOff = null,Object? repeat = null,Object? seriesId = null,Object? dayIndex = null,Object? dayCount = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? pictureCount = null,Object? startedAt = freezed,Object? completedAt = freezed,}) {
  return _then(AppointmentRecord(
startTime: null == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime,endTime: null == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,clientId: null == clientId ? _self.clientId : clientId // ignore: cast_nullable_to_non_nullable
as String,clientName: null == clientName ? _self.clientName : clientName // ignore: cast_nullable_to_non_nullable
as String,clientPhone: null == clientPhone ? _self.clientPhone : clientPhone // ignore: cast_nullable_to_non_nullable
as String,employeeIds: null == employeeIds ? _self.employeeIds : employeeIds // ignore: cast_nullable_to_non_nullable
as List<String>,employeeNames: null == employeeNames ? _self.employeeNames : employeeNames // ignore: cast_nullable_to_non_nullable
as List<String>,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,fieldNotes: null == fieldNotes ? _self.fieldNotes : fieldNotes // ignore: cast_nullable_to_non_nullable
as String,materialsNeeded: null == materialsNeeded ? _self.materialsNeeded : materialsNeeded // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,isPersonal: null == isPersonal ? _self.isPersonal : isPersonal // ignore: cast_nullable_to_non_nullable
as bool,isAllDay: null == isAllDay ? _self.isAllDay : isAllDay // ignore: cast_nullable_to_non_nullable
as bool,isDayOff: null == isDayOff ? _self.isDayOff : isDayOff // ignore: cast_nullable_to_non_nullable
as bool,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,seriesId: null == seriesId ? _self.seriesId : seriesId // ignore: cast_nullable_to_non_nullable
as String,dayIndex: null == dayIndex ? _self.dayIndex : dayIndex // ignore: cast_nullable_to_non_nullable
as int,dayCount: null == dayCount ? _self.dayCount : dayCount // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pictureCount: null == pictureCount ? _self.pictureCount : pictureCount // ignore: cast_nullable_to_non_nullable
as int,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [AppointmentRecord].
extension AppointmentRecordPatterns on AppointmentRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppointmentRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppointmentRecord value)  $default,){
final _that = this;
switch (_that) {
case _AppointmentRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppointmentRecord value)?  $default,){
final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime startTime,  DateTime endTime,  String? id,  String title,  String clientId,  String clientName,  String clientPhone,  List<String> employeeIds,  List<String> employeeNames,  String address,  String notes,  String fieldNotes,  String materialsNeeded,  String status,  bool isPersonal,  bool isAllDay,  bool isDayOff,  RepeatInterval repeat,  String seriesId,  int dayIndex,  int dayCount,  DateTime? createdAt,  DateTime? updatedAt,  int pictureCount,  DateTime? startedAt,  DateTime? completedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
return $default(_that.startTime,_that.endTime,_that.id,_that.title,_that.clientId,_that.clientName,_that.clientPhone,_that.employeeIds,_that.employeeNames,_that.address,_that.notes,_that.fieldNotes,_that.materialsNeeded,_that.status,_that.isPersonal,_that.isAllDay,_that.isDayOff,_that.repeat,_that.seriesId,_that.dayIndex,_that.dayCount,_that.createdAt,_that.updatedAt,_that.pictureCount,_that.startedAt,_that.completedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime startTime,  DateTime endTime,  String? id,  String title,  String clientId,  String clientName,  String clientPhone,  List<String> employeeIds,  List<String> employeeNames,  String address,  String notes,  String fieldNotes,  String materialsNeeded,  String status,  bool isPersonal,  bool isAllDay,  bool isDayOff,  RepeatInterval repeat,  String seriesId,  int dayIndex,  int dayCount,  DateTime? createdAt,  DateTime? updatedAt,  int pictureCount,  DateTime? startedAt,  DateTime? completedAt)  $default,) {final _that = this;
switch (_that) {
case _AppointmentRecord():
return $default(_that.startTime,_that.endTime,_that.id,_that.title,_that.clientId,_that.clientName,_that.clientPhone,_that.employeeIds,_that.employeeNames,_that.address,_that.notes,_that.fieldNotes,_that.materialsNeeded,_that.status,_that.isPersonal,_that.isAllDay,_that.isDayOff,_that.repeat,_that.seriesId,_that.dayIndex,_that.dayCount,_that.createdAt,_that.updatedAt,_that.pictureCount,_that.startedAt,_that.completedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime startTime,  DateTime endTime,  String? id,  String title,  String clientId,  String clientName,  String clientPhone,  List<String> employeeIds,  List<String> employeeNames,  String address,  String notes,  String fieldNotes,  String materialsNeeded,  String status,  bool isPersonal,  bool isAllDay,  bool isDayOff,  RepeatInterval repeat,  String seriesId,  int dayIndex,  int dayCount,  DateTime? createdAt,  DateTime? updatedAt,  int pictureCount,  DateTime? startedAt,  DateTime? completedAt)?  $default,) {final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
return $default(_that.startTime,_that.endTime,_that.id,_that.title,_that.clientId,_that.clientName,_that.clientPhone,_that.employeeIds,_that.employeeNames,_that.address,_that.notes,_that.fieldNotes,_that.materialsNeeded,_that.status,_that.isPersonal,_that.isAllDay,_that.isDayOff,_that.repeat,_that.seriesId,_that.dayIndex,_that.dayCount,_that.createdAt,_that.updatedAt,_that.pictureCount,_that.startedAt,_that.completedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AppointmentRecord extends AppointmentRecord {
  const _AppointmentRecord({required this.startTime, required this.endTime, this.id, this.title = '', this.clientId = '', this.clientName = '', this.clientPhone = '',  List<String> employeeIds = const <String>[],  List<String> employeeNames = const <String>[], this.address = '', this.notes = '', this.fieldNotes = '', this.materialsNeeded = '', this.status = 'pending', this.isPersonal = false, this.isAllDay = false, this.isDayOff = false, this.repeat = RepeatInterval.none, this.seriesId = '', this.dayIndex = 0, this.dayCount = 0, this.createdAt, this.updatedAt, this.pictureCount = 0, this.startedAt, this.completedAt}): _employeeIds = employeeIds,_employeeNames = employeeNames,super._();
  

@override final  DateTime startTime;
@override final  DateTime endTime;
@override final  String? id;
@override@JsonKey() final  String title;
@override@JsonKey() final  String clientId;
@override@JsonKey() final  String clientName;
@override@JsonKey() final  String clientPhone;
 final  List<String> _employeeIds;
@override@JsonKey() List<String> get employeeIds {
  if (_employeeIds is EqualUnmodifiableListView) return _employeeIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_employeeIds);
}

 final  List<String> _employeeNames;
@override@JsonKey() List<String> get employeeNames {
  if (_employeeNames is EqualUnmodifiableListView) return _employeeNames;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_employeeNames);
}

@override@JsonKey() final  String address;
@override@JsonKey() final  String notes;
@override@JsonKey() final  String fieldNotes;
@override@JsonKey() final  String materialsNeeded;
@override@JsonKey() final  String status;
@override@JsonKey() final  bool isPersonal;
@override@JsonKey() final  bool isAllDay;
@override@JsonKey() final  bool isDayOff;
@override@JsonKey() final  RepeatInterval repeat;
@override@JsonKey() final  String seriesId;
@override@JsonKey() final  int dayIndex;
@override@JsonKey() final  int dayCount;
@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;
@override@JsonKey() final  int pictureCount;
@override final  DateTime? startedAt;
@override final  DateTime? completedAt;

/// Create a copy of AppointmentRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppointmentRecordCopyWith<_AppointmentRecord> get copyWith => __$AppointmentRecordCopyWithImpl<_AppointmentRecord>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppointmentRecord&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.clientId, clientId) || other.clientId == clientId)&&(identical(other.clientName, clientName) || other.clientName == clientName)&&(identical(other.clientPhone, clientPhone) || other.clientPhone == clientPhone)&&const DeepCollectionEquality().equals(other.employeeIds, _employeeIds)&&const DeepCollectionEquality().equals(other.employeeNames, _employeeNames)&&(identical(other.address, address) || other.address == address)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.fieldNotes, fieldNotes) || other.fieldNotes == fieldNotes)&&(identical(other.materialsNeeded, materialsNeeded) || other.materialsNeeded == materialsNeeded)&&(identical(other.status, status) || other.status == status)&&(identical(other.isPersonal, isPersonal) || other.isPersonal == isPersonal)&&(identical(other.isAllDay, isAllDay) || other.isAllDay == isAllDay)&&(identical(other.isDayOff, isDayOff) || other.isDayOff == isDayOff)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.seriesId, seriesId) || other.seriesId == seriesId)&&(identical(other.dayIndex, dayIndex) || other.dayIndex == dayIndex)&&(identical(other.dayCount, dayCount) || other.dayCount == dayCount)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.pictureCount, pictureCount) || other.pictureCount == pictureCount)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,startTime,endTime,id,title,clientId,clientName,clientPhone,const DeepCollectionEquality().hash(_employeeIds),const DeepCollectionEquality().hash(_employeeNames),address,notes,fieldNotes,materialsNeeded,status,isPersonal,isAllDay,isDayOff,repeat,seriesId,dayIndex,dayCount,createdAt,updatedAt,pictureCount,startedAt,completedAt]);
}

@override
String toString() {
    return 'AppointmentRecord(startTime: $startTime, endTime: $endTime, id: $id, title: $title, clientId: $clientId, clientName: $clientName, clientPhone: $clientPhone, employeeIds: $employeeIds, employeeNames: $employeeNames, address: $address, notes: $notes, fieldNotes: $fieldNotes, materialsNeeded: $materialsNeeded, status: $status, isPersonal: $isPersonal, isAllDay: $isAllDay, isDayOff: $isDayOff, repeat: $repeat, seriesId: $seriesId, dayIndex: $dayIndex, dayCount: $dayCount, createdAt: $createdAt, updatedAt: $updatedAt, pictureCount: $pictureCount, startedAt: $startedAt, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class _$AppointmentRecordCopyWith<$Res> implements $AppointmentRecordCopyWith<$Res> {
  factory _$AppointmentRecordCopyWith(_AppointmentRecord value, $Res Function(_AppointmentRecord) _then) = __$AppointmentRecordCopyWithImpl;
@override @useResult
$Res call({
 DateTime startTime, DateTime endTime, String? id, String title, String clientId, String clientName, String clientPhone, List<String> employeeIds, List<String> employeeNames, String address, String notes, String fieldNotes, String materialsNeeded, String status, bool isPersonal, bool isAllDay, bool isDayOff, RepeatInterval repeat, String seriesId, int dayIndex, int dayCount, DateTime? createdAt, DateTime? updatedAt, int pictureCount, DateTime? startedAt, DateTime? completedAt
});




}
/// @nodoc
class __$AppointmentRecordCopyWithImpl<$Res>
    implements _$AppointmentRecordCopyWith<$Res> {
  __$AppointmentRecordCopyWithImpl(this._self, this._then);

  final _AppointmentRecord _self;
  final $Res Function(_AppointmentRecord) _then;

/// Create a copy of AppointmentRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? startTime = null,Object? endTime = null,Object? id = freezed,Object? title = null,Object? clientId = null,Object? clientName = null,Object? clientPhone = null,Object? employeeIds = null,Object? employeeNames = null,Object? address = null,Object? notes = null,Object? fieldNotes = null,Object? materialsNeeded = null,Object? status = null,Object? isPersonal = null,Object? isAllDay = null,Object? isDayOff = null,Object? repeat = null,Object? seriesId = null,Object? dayIndex = null,Object? dayCount = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? pictureCount = null,Object? startedAt = freezed,Object? completedAt = freezed,}) {
  return _then(_AppointmentRecord(
startTime: null == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime,endTime: null == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,clientId: null == clientId ? _self.clientId : clientId // ignore: cast_nullable_to_non_nullable
as String,clientName: null == clientName ? _self.clientName : clientName // ignore: cast_nullable_to_non_nullable
as String,clientPhone: null == clientPhone ? _self.clientPhone : clientPhone // ignore: cast_nullable_to_non_nullable
as String,employeeIds: null == employeeIds ? _self._employeeIds : employeeIds // ignore: cast_nullable_to_non_nullable
as List<String>,employeeNames: null == employeeNames ? _self._employeeNames : employeeNames // ignore: cast_nullable_to_non_nullable
as List<String>,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,fieldNotes: null == fieldNotes ? _self.fieldNotes : fieldNotes // ignore: cast_nullable_to_non_nullable
as String,materialsNeeded: null == materialsNeeded ? _self.materialsNeeded : materialsNeeded // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,isPersonal: null == isPersonal ? _self.isPersonal : isPersonal // ignore: cast_nullable_to_non_nullable
as bool,isAllDay: null == isAllDay ? _self.isAllDay : isAllDay // ignore: cast_nullable_to_non_nullable
as bool,isDayOff: null == isDayOff ? _self.isDayOff : isDayOff // ignore: cast_nullable_to_non_nullable
as bool,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,seriesId: null == seriesId ? _self.seriesId : seriesId // ignore: cast_nullable_to_non_nullable
as String,dayIndex: null == dayIndex ? _self.dayIndex : dayIndex // ignore: cast_nullable_to_non_nullable
as int,dayCount: null == dayCount ? _self.dayCount : dayCount // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pictureCount: null == pictureCount ? _self.pictureCount : pictureCount // ignore: cast_nullable_to_non_nullable
as int,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
