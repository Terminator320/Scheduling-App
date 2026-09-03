// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppointmentRecord {

 DateTime get startTime; DateTime get endTime; String? get id; String get title; String get clientId; String get clientName; String get clientPhone; List<String> get employeeIds; List<String> get employeeNames; String get address; String get notes;// What the CREW recorded on site, as distinct from [notes], which the
// dispatcher writes when booking.
 String get fieldNotes; String get materialsNeeded; String get status;// Personal jobs block crew time without client fields.
 bool get isPersonal;// All-day jobs still store real start/end instants.
 bool get isAllDay;// Day off is meaningful only through [isTimeOff].
 bool get isDayOff; RepeatInterval get repeat;// Links repeat occurrences or split days for one multi-day run.
 String get seriesId;// Multi-day run labels; read through `AppointmentDaySlice.sliceFor`.
 int get dayIndex; int get dayCount; DateTime? get createdAt; DateTime? get updatedAt;// Parent-card photo indicator, owned by server recounts after create.
 int get pictureCount;// The job time record. Both are stamped SERVER-SIDE by the appointment
// write trigger on the status transition (`lifecycleStamps` in
// `functions/notification_policy.js`), never by a client.
 DateTime? get startedAt; DateTime? get completedAt;
/// Create a copy of AppointmentRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppointmentRecordCopyWith<AppointmentRecord> get copyWith => _$AppointmentRecordCopyWithImpl<AppointmentRecord>(this as AppointmentRecord, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppointmentRecord&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.clientId, clientId) || other.clientId == clientId)&&(identical(other.clientName, clientName) || other.clientName == clientName)&&(identical(other.clientPhone, clientPhone) || other.clientPhone == clientPhone)&&const DeepCollectionEquality().equals(other.employeeIds, employeeIds)&&const DeepCollectionEquality().equals(other.employeeNames, employeeNames)&&(identical(other.address, address) || other.address == address)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.fieldNotes, fieldNotes) || other.fieldNotes == fieldNotes)&&(identical(other.materialsNeeded, materialsNeeded) || other.materialsNeeded == materialsNeeded)&&(identical(other.status, status) || other.status == status)&&(identical(other.isPersonal, isPersonal) || other.isPersonal == isPersonal)&&(identical(other.isAllDay, isAllDay) || other.isAllDay == isAllDay)&&(identical(other.isDayOff, isDayOff) || other.isDayOff == isDayOff)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.seriesId, seriesId) || other.seriesId == seriesId)&&(identical(other.dayIndex, dayIndex) || other.dayIndex == dayIndex)&&(identical(other.dayCount, dayCount) || other.dayCount == dayCount)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.pictureCount, pictureCount) || other.pictureCount == pictureCount)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hashAll([runtimeType,startTime,endTime,id,title,clientId,clientName,clientPhone,const DeepCollectionEquality().hash(employeeIds),const DeepCollectionEquality().hash(employeeNames),address,notes,fieldNotes,materialsNeeded,status,isPersonal,isAllDay,isDayOff,repeat,seriesId,dayIndex,dayCount,createdAt,updatedAt,pictureCount,startedAt,completedAt]);

@override
String toString() {
  return 'AppointmentRecord(startTime: $startTime, endTime: $endTime, id: $id, title: $title, clientId: $clientId, clientName: $clientName, clientPhone: $clientPhone, employeeIds: $employeeIds, employeeNames: $employeeNames, address: $address, notes: $notes, fieldNotes: $fieldNotes, materialsNeeded: $materialsNeeded, status: $status, isPersonal: $isPersonal, isAllDay: $isAllDay, isDayOff: $isDayOff, repeat: $repeat, seriesId: $seriesId, dayIndex: $dayIndex, dayCount: $dayCount, createdAt: $createdAt, updatedAt: $updatedAt, pictureCount: $pictureCount, startedAt: $startedAt, completedAt: $completedAt)';
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
  return _then(_self.copyWith(
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
  const _AppointmentRecord({required this.startTime, required this.endTime, this.id, this.title = '', this.clientId = '', this.clientName = '', this.clientPhone = '', final  List<String> employeeIds = const <String>[], final  List<String> employeeNames = const <String>[], this.address = '', this.notes = '', this.fieldNotes = '', this.materialsNeeded = '', this.status = 'pending', this.isPersonal = false, this.isAllDay = false, this.isDayOff = false, this.repeat = RepeatInterval.none, this.seriesId = '', this.dayIndex = 0, this.dayCount = 0, this.createdAt, this.updatedAt, this.pictureCount = 0, this.startedAt, this.completedAt}): _employeeIds = employeeIds,_employeeNames = employeeNames,super._();
  

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
// What the CREW recorded on site, as distinct from [notes], which the
// dispatcher writes when booking.
@override@JsonKey() final  String fieldNotes;
@override@JsonKey() final  String materialsNeeded;
@override@JsonKey() final  String status;
// Personal jobs block crew time without client fields.
@override@JsonKey() final  bool isPersonal;
// All-day jobs still store real start/end instants.
@override@JsonKey() final  bool isAllDay;
// Day off is meaningful only through [isTimeOff].
@override@JsonKey() final  bool isDayOff;
@override@JsonKey() final  RepeatInterval repeat;
// Links repeat occurrences or split days for one multi-day run.
@override@JsonKey() final  String seriesId;
// Multi-day run labels; read through `AppointmentDaySlice.sliceFor`.
@override@JsonKey() final  int dayIndex;
@override@JsonKey() final  int dayCount;
@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;
// Parent-card photo indicator, owned by server recounts after create.
@override@JsonKey() final  int pictureCount;
// The job time record. Both are stamped SERVER-SIDE by the appointment
// write trigger on the status transition (`lifecycleStamps` in
// `functions/notification_policy.js`), never by a client.
@override final  DateTime? startedAt;
@override final  DateTime? completedAt;

/// Create a copy of AppointmentRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppointmentRecordCopyWith<_AppointmentRecord> get copyWith => __$AppointmentRecordCopyWithImpl<_AppointmentRecord>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppointmentRecord&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.clientId, clientId) || other.clientId == clientId)&&(identical(other.clientName, clientName) || other.clientName == clientName)&&(identical(other.clientPhone, clientPhone) || other.clientPhone == clientPhone)&&const DeepCollectionEquality().equals(other._employeeIds, _employeeIds)&&const DeepCollectionEquality().equals(other._employeeNames, _employeeNames)&&(identical(other.address, address) || other.address == address)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.fieldNotes, fieldNotes) || other.fieldNotes == fieldNotes)&&(identical(other.materialsNeeded, materialsNeeded) || other.materialsNeeded == materialsNeeded)&&(identical(other.status, status) || other.status == status)&&(identical(other.isPersonal, isPersonal) || other.isPersonal == isPersonal)&&(identical(other.isAllDay, isAllDay) || other.isAllDay == isAllDay)&&(identical(other.isDayOff, isDayOff) || other.isDayOff == isDayOff)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.seriesId, seriesId) || other.seriesId == seriesId)&&(identical(other.dayIndex, dayIndex) || other.dayIndex == dayIndex)&&(identical(other.dayCount, dayCount) || other.dayCount == dayCount)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.pictureCount, pictureCount) || other.pictureCount == pictureCount)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hashAll([runtimeType,startTime,endTime,id,title,clientId,clientName,clientPhone,const DeepCollectionEquality().hash(_employeeIds),const DeepCollectionEquality().hash(_employeeNames),address,notes,fieldNotes,materialsNeeded,status,isPersonal,isAllDay,isDayOff,repeat,seriesId,dayIndex,dayCount,createdAt,updatedAt,pictureCount,startedAt,completedAt]);

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
