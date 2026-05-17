// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment_record.dart';

T _$identity<T>(T value) => value;
mixin _$AppointmentRecord {

 DateTime get startTime; DateTime get endTime; String? get id; String get title; String get clientId; String get clientName; String get clientPhone; List<String> get employeeIds; List<String> get employeeNames; String get address; String get notes; String get materialsNeeded; String get status; DateTime? get createdAt; DateTime? get updatedAt; List<AppointmentImage> get pictures;
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppointmentRecordCopyWith<AppointmentRecord> get copyWith => _$AppointmentRecordCopyWithImpl<AppointmentRecord>(this as AppointmentRecord, _$identity);

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppointmentRecord&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.clientId, clientId) || other.clientId == clientId)&&(identical(other.clientName, clientName) || other.clientName == clientName)&&(identical(other.clientPhone, clientPhone) || other.clientPhone == clientPhone)&&const DeepCollectionEquality().equals(other.employeeIds, employeeIds)&&const DeepCollectionEquality().equals(other.employeeNames, employeeNames)&&(identical(other.address, address) || other.address == address)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.materialsNeeded, materialsNeeded) || other.materialsNeeded == materialsNeeded)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.pictures, pictures));
}

@override
int get hashCode => Object.hash(runtimeType,startTime,endTime,id,title,clientId,clientName,clientPhone,const DeepCollectionEquality().hash(employeeIds),const DeepCollectionEquality().hash(employeeNames),address,notes,materialsNeeded,status,createdAt,updatedAt,const DeepCollectionEquality().hash(pictures));

@override
String toString() {
  return 'AppointmentRecord(startTime: $startTime, endTime: $endTime, id: $id, title: $title, clientId: $clientId, clientName: $clientName, clientPhone: $clientPhone, employeeIds: $employeeIds, employeeNames: $employeeNames, address: $address, notes: $notes, materialsNeeded: $materialsNeeded, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, pictures: $pictures)';
}

}

abstract mixin class $AppointmentRecordCopyWith<$Res>  {
  factory $AppointmentRecordCopyWith(AppointmentRecord value, $Res Function(AppointmentRecord) _then) = _$AppointmentRecordCopyWithImpl;
@useResult
$Res call({
 DateTime startTime, DateTime endTime, String? id, String title, String clientId, String clientName, String clientPhone, List<String> employeeIds, List<String> employeeNames, String address, String notes, String materialsNeeded, String status, DateTime? createdAt, DateTime? updatedAt, List<AppointmentImage> pictures
});

}
class _$AppointmentRecordCopyWithImpl<$Res>
    implements $AppointmentRecordCopyWith<$Res> {
  _$AppointmentRecordCopyWithImpl(this._self, this._then);

  final AppointmentRecord _self;
  final $Res Function(AppointmentRecord) _then;

@pragma('vm:prefer-inline') @override $Res call({Object? startTime = null,Object? endTime = null,Object? id = freezed,Object? title = null,Object? clientId = null,Object? clientName = null,Object? clientPhone = null,Object? employeeIds = null,Object? employeeNames = null,Object? address = null,Object? notes = null,Object? materialsNeeded = null,Object? status = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? pictures = null,}) {
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
as String,materialsNeeded: null == materialsNeeded ? _self.materialsNeeded : materialsNeeded // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pictures: null == pictures ? _self.pictures : pictures // ignore: cast_nullable_to_non_nullable
as List<AppointmentImage>,
  ));
}

}

extension AppointmentRecordPatterns on AppointmentRecord {

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppointmentRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
return $default(_that);case _:
  return orElse();

}
}

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppointmentRecord value)  $default,){
final _that = this;
switch (_that) {
case _AppointmentRecord():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppointmentRecord value)?  $default,){
final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
return $default(_that);case _:
  return null;

}
}

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime startTime,  DateTime endTime,  String? id,  String title,  String clientId,  String clientName,  String clientPhone,  List<String> employeeIds,  List<String> employeeNames,  String address,  String notes,  String materialsNeeded,  String status,  DateTime? createdAt,  DateTime? updatedAt,  List<AppointmentImage> pictures)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
return $default(_that.startTime,_that.endTime,_that.id,_that.title,_that.clientId,_that.clientName,_that.clientPhone,_that.employeeIds,_that.employeeNames,_that.address,_that.notes,_that.materialsNeeded,_that.status,_that.createdAt,_that.updatedAt,_that.pictures);case _:
  return orElse();

}
}

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime startTime,  DateTime endTime,  String? id,  String title,  String clientId,  String clientName,  String clientPhone,  List<String> employeeIds,  List<String> employeeNames,  String address,  String notes,  String materialsNeeded,  String status,  DateTime? createdAt,  DateTime? updatedAt,  List<AppointmentImage> pictures)  $default,) {final _that = this;
switch (_that) {
case _AppointmentRecord():
return $default(_that.startTime,_that.endTime,_that.id,_that.title,_that.clientId,_that.clientName,_that.clientPhone,_that.employeeIds,_that.employeeNames,_that.address,_that.notes,_that.materialsNeeded,_that.status,_that.createdAt,_that.updatedAt,_that.pictures);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime startTime,  DateTime endTime,  String? id,  String title,  String clientId,  String clientName,  String clientPhone,  List<String> employeeIds,  List<String> employeeNames,  String address,  String notes,  String materialsNeeded,  String status,  DateTime? createdAt,  DateTime? updatedAt,  List<AppointmentImage> pictures)?  $default,) {final _that = this;
switch (_that) {
case _AppointmentRecord() when $default != null:
return $default(_that.startTime,_that.endTime,_that.id,_that.title,_that.clientId,_that.clientName,_that.clientPhone,_that.employeeIds,_that.employeeNames,_that.address,_that.notes,_that.materialsNeeded,_that.status,_that.createdAt,_that.updatedAt,_that.pictures);case _:
  return null;

}
}

}

class _AppointmentRecord extends AppointmentRecord {
  const _AppointmentRecord({required this.startTime, required this.endTime, this.id, this.title = '', this.clientId = '', this.clientName = '', this.clientPhone = '', final  List<String> employeeIds = const <String>[], final  List<String> employeeNames = const <String>[], this.address = '', this.notes = '', this.materialsNeeded = '', this.status = 'pending', this.createdAt, this.updatedAt, final  List<AppointmentImage> pictures = const <AppointmentImage>[]}): _employeeIds = employeeIds,_employeeNames = employeeNames,_pictures = pictures,super._();
  
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
@override@JsonKey() final  String materialsNeeded;
@override@JsonKey() final  String status;
@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;
 final  List<AppointmentImage> _pictures;
@override@JsonKey() List<AppointmentImage> get pictures {
  if (_pictures is EqualUnmodifiableListView) return _pictures;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pictures);
}

@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppointmentRecordCopyWith<_AppointmentRecord> get copyWith => __$AppointmentRecordCopyWithImpl<_AppointmentRecord>(this, _$identity);

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppointmentRecord&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.clientId, clientId) || other.clientId == clientId)&&(identical(other.clientName, clientName) || other.clientName == clientName)&&(identical(other.clientPhone, clientPhone) || other.clientPhone == clientPhone)&&const DeepCollectionEquality().equals(other._employeeIds, _employeeIds)&&const DeepCollectionEquality().equals(other._employeeNames, _employeeNames)&&(identical(other.address, address) || other.address == address)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.materialsNeeded, materialsNeeded) || other.materialsNeeded == materialsNeeded)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other._pictures, _pictures));
}

@override
int get hashCode => Object.hash(runtimeType,startTime,endTime,id,title,clientId,clientName,clientPhone,const DeepCollectionEquality().hash(_employeeIds),const DeepCollectionEquality().hash(_employeeNames),address,notes,materialsNeeded,status,createdAt,updatedAt,const DeepCollectionEquality().hash(_pictures));

@override
String toString() {
  return 'AppointmentRecord(startTime: $startTime, endTime: $endTime, id: $id, title: $title, clientId: $clientId, clientName: $clientName, clientPhone: $clientPhone, employeeIds: $employeeIds, employeeNames: $employeeNames, address: $address, notes: $notes, materialsNeeded: $materialsNeeded, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, pictures: $pictures)';
}

}

abstract mixin class _$AppointmentRecordCopyWith<$Res> implements $AppointmentRecordCopyWith<$Res> {
  factory _$AppointmentRecordCopyWith(_AppointmentRecord value, $Res Function(_AppointmentRecord) _then) = __$AppointmentRecordCopyWithImpl;
@override @useResult
$Res call({
 DateTime startTime, DateTime endTime, String? id, String title, String clientId, String clientName, String clientPhone, List<String> employeeIds, List<String> employeeNames, String address, String notes, String materialsNeeded, String status, DateTime? createdAt, DateTime? updatedAt, List<AppointmentImage> pictures
});

}
class __$AppointmentRecordCopyWithImpl<$Res>
    implements _$AppointmentRecordCopyWith<$Res> {
  __$AppointmentRecordCopyWithImpl(this._self, this._then);

  final _AppointmentRecord _self;
  final $Res Function(_AppointmentRecord) _then;

@override @pragma('vm:prefer-inline') $Res call({Object? startTime = null,Object? endTime = null,Object? id = freezed,Object? title = null,Object? clientId = null,Object? clientName = null,Object? clientPhone = null,Object? employeeIds = null,Object? employeeNames = null,Object? address = null,Object? notes = null,Object? materialsNeeded = null,Object? status = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? pictures = null,}) {
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
as String,materialsNeeded: null == materialsNeeded ? _self.materialsNeeded : materialsNeeded // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pictures: null == pictures ? _self._pictures : pictures // ignore: cast_nullable_to_non_nullable
as List<AppointmentImage>,
  ));
}

}

