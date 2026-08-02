// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'employee_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EmployeeRecord {

 String get id; String get name; String get firstName; String get lastName; String get email; String get phone;// Legacy default (Material blue) for docs predating the color palette —
// changing this recolors those employees.
 Color get color; String get role; String get status; String get uid; JobTitle get jobTitle; List<bool> get workingDays; int get workStartMinutes; int get workEndMinutes;// 0 means no cap.
 int get maxJobsPerDay; bool get onCall; String get emergencyContact; String get emergencyPhone;
/// Create a copy of EmployeeRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EmployeeRecordCopyWith<EmployeeRecord> get copyWith => _$EmployeeRecordCopyWithImpl<EmployeeRecord>(this as EmployeeRecord, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EmployeeRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.firstName, firstName) || other.firstName == firstName)&&(identical(other.lastName, lastName) || other.lastName == lastName)&&(identical(other.email, email) || other.email == email)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.color, color) || other.color == color)&&(identical(other.role, role) || other.role == role)&&(identical(other.status, status) || other.status == status)&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.jobTitle, jobTitle) || other.jobTitle == jobTitle)&&const DeepCollectionEquality().equals(other.workingDays, workingDays)&&(identical(other.workStartMinutes, workStartMinutes) || other.workStartMinutes == workStartMinutes)&&(identical(other.workEndMinutes, workEndMinutes) || other.workEndMinutes == workEndMinutes)&&(identical(other.maxJobsPerDay, maxJobsPerDay) || other.maxJobsPerDay == maxJobsPerDay)&&(identical(other.onCall, onCall) || other.onCall == onCall)&&(identical(other.emergencyContact, emergencyContact) || other.emergencyContact == emergencyContact)&&(identical(other.emergencyPhone, emergencyPhone) || other.emergencyPhone == emergencyPhone));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,firstName,lastName,email,phone,color,role,status,uid,jobTitle,const DeepCollectionEquality().hash(workingDays),workStartMinutes,workEndMinutes,maxJobsPerDay,onCall,emergencyContact,emergencyPhone);

@override
String toString() {
  return 'EmployeeRecord(id: $id, name: $name, firstName: $firstName, lastName: $lastName, email: $email, phone: $phone, color: $color, role: $role, status: $status, uid: $uid, jobTitle: $jobTitle, workingDays: $workingDays, workStartMinutes: $workStartMinutes, workEndMinutes: $workEndMinutes, maxJobsPerDay: $maxJobsPerDay, onCall: $onCall, emergencyContact: $emergencyContact, emergencyPhone: $emergencyPhone)';
}


}

/// @nodoc
abstract mixin class $EmployeeRecordCopyWith<$Res>  {
  factory $EmployeeRecordCopyWith(EmployeeRecord value, $Res Function(EmployeeRecord) _then) = _$EmployeeRecordCopyWithImpl;
@useResult
$Res call({
 String id, String name, String firstName, String lastName, String email, String phone, Color color, String role, String status, String uid, JobTitle jobTitle, List<bool> workingDays, int workStartMinutes, int workEndMinutes, int maxJobsPerDay, bool onCall, String emergencyContact, String emergencyPhone
});




}
/// @nodoc
class _$EmployeeRecordCopyWithImpl<$Res>
    implements $EmployeeRecordCopyWith<$Res> {
  _$EmployeeRecordCopyWithImpl(this._self, this._then);

  final EmployeeRecord _self;
  final $Res Function(EmployeeRecord) _then;

/// Create a copy of EmployeeRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? firstName = null,Object? lastName = null,Object? email = null,Object? phone = null,Object? color = null,Object? role = null,Object? status = null,Object? uid = null,Object? jobTitle = null,Object? workingDays = null,Object? workStartMinutes = null,Object? workEndMinutes = null,Object? maxJobsPerDay = null,Object? onCall = null,Object? emergencyContact = null,Object? emergencyPhone = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,firstName: null == firstName ? _self.firstName : firstName // ignore: cast_nullable_to_non_nullable
as String,lastName: null == lastName ? _self.lastName : lastName // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as Color,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,jobTitle: null == jobTitle ? _self.jobTitle : jobTitle // ignore: cast_nullable_to_non_nullable
as JobTitle,workingDays: null == workingDays ? _self.workingDays : workingDays // ignore: cast_nullable_to_non_nullable
as List<bool>,workStartMinutes: null == workStartMinutes ? _self.workStartMinutes : workStartMinutes // ignore: cast_nullable_to_non_nullable
as int,workEndMinutes: null == workEndMinutes ? _self.workEndMinutes : workEndMinutes // ignore: cast_nullable_to_non_nullable
as int,maxJobsPerDay: null == maxJobsPerDay ? _self.maxJobsPerDay : maxJobsPerDay // ignore: cast_nullable_to_non_nullable
as int,onCall: null == onCall ? _self.onCall : onCall // ignore: cast_nullable_to_non_nullable
as bool,emergencyContact: null == emergencyContact ? _self.emergencyContact : emergencyContact // ignore: cast_nullable_to_non_nullable
as String,emergencyPhone: null == emergencyPhone ? _self.emergencyPhone : emergencyPhone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [EmployeeRecord].
extension EmployeeRecordPatterns on EmployeeRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EmployeeRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EmployeeRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EmployeeRecord value)  $default,){
final _that = this;
switch (_that) {
case _EmployeeRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EmployeeRecord value)?  $default,){
final _that = this;
switch (_that) {
case _EmployeeRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String firstName,  String lastName,  String email,  String phone,  Color color,  String role,  String status,  String uid,  JobTitle jobTitle,  List<bool> workingDays,  int workStartMinutes,  int workEndMinutes,  int maxJobsPerDay,  bool onCall,  String emergencyContact,  String emergencyPhone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EmployeeRecord() when $default != null:
return $default(_that.id,_that.name,_that.firstName,_that.lastName,_that.email,_that.phone,_that.color,_that.role,_that.status,_that.uid,_that.jobTitle,_that.workingDays,_that.workStartMinutes,_that.workEndMinutes,_that.maxJobsPerDay,_that.onCall,_that.emergencyContact,_that.emergencyPhone);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String firstName,  String lastName,  String email,  String phone,  Color color,  String role,  String status,  String uid,  JobTitle jobTitle,  List<bool> workingDays,  int workStartMinutes,  int workEndMinutes,  int maxJobsPerDay,  bool onCall,  String emergencyContact,  String emergencyPhone)  $default,) {final _that = this;
switch (_that) {
case _EmployeeRecord():
return $default(_that.id,_that.name,_that.firstName,_that.lastName,_that.email,_that.phone,_that.color,_that.role,_that.status,_that.uid,_that.jobTitle,_that.workingDays,_that.workStartMinutes,_that.workEndMinutes,_that.maxJobsPerDay,_that.onCall,_that.emergencyContact,_that.emergencyPhone);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String firstName,  String lastName,  String email,  String phone,  Color color,  String role,  String status,  String uid,  JobTitle jobTitle,  List<bool> workingDays,  int workStartMinutes,  int workEndMinutes,  int maxJobsPerDay,  bool onCall,  String emergencyContact,  String emergencyPhone)?  $default,) {final _that = this;
switch (_that) {
case _EmployeeRecord() when $default != null:
return $default(_that.id,_that.name,_that.firstName,_that.lastName,_that.email,_that.phone,_that.color,_that.role,_that.status,_that.uid,_that.jobTitle,_that.workingDays,_that.workStartMinutes,_that.workEndMinutes,_that.maxJobsPerDay,_that.onCall,_that.emergencyContact,_that.emergencyPhone);case _:
  return null;

}
}

}

/// @nodoc


class _EmployeeRecord extends EmployeeRecord {
  const _EmployeeRecord({required this.id, this.name = '', this.firstName = '', this.lastName = '', this.email = '', this.phone = '', this.color = const Color(0xFF2196F3), this.role = 'employee', this.status = '', this.uid = '', this.jobTitle = JobTitle.unset, final  List<bool> workingDays = kDefaultWorkingDays, this.workStartMinutes = kDefaultWorkStartMinutes, this.workEndMinutes = kDefaultWorkEndMinutes, this.maxJobsPerDay = 0, this.onCall = false, this.emergencyContact = '', this.emergencyPhone = ''}): _workingDays = workingDays,super._();
  

@override final  String id;
@override@JsonKey() final  String name;
@override@JsonKey() final  String firstName;
@override@JsonKey() final  String lastName;
@override@JsonKey() final  String email;
@override@JsonKey() final  String phone;
// Legacy default (Material blue) for docs predating the color palette —
// changing this recolors those employees.
@override@JsonKey() final  Color color;
@override@JsonKey() final  String role;
@override@JsonKey() final  String status;
@override@JsonKey() final  String uid;
@override@JsonKey() final  JobTitle jobTitle;
 final  List<bool> _workingDays;
@override@JsonKey() List<bool> get workingDays {
  if (_workingDays is EqualUnmodifiableListView) return _workingDays;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_workingDays);
}

@override@JsonKey() final  int workStartMinutes;
@override@JsonKey() final  int workEndMinutes;
// 0 means no cap.
@override@JsonKey() final  int maxJobsPerDay;
@override@JsonKey() final  bool onCall;
@override@JsonKey() final  String emergencyContact;
@override@JsonKey() final  String emergencyPhone;

/// Create a copy of EmployeeRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EmployeeRecordCopyWith<_EmployeeRecord> get copyWith => __$EmployeeRecordCopyWithImpl<_EmployeeRecord>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EmployeeRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.firstName, firstName) || other.firstName == firstName)&&(identical(other.lastName, lastName) || other.lastName == lastName)&&(identical(other.email, email) || other.email == email)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.color, color) || other.color == color)&&(identical(other.role, role) || other.role == role)&&(identical(other.status, status) || other.status == status)&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.jobTitle, jobTitle) || other.jobTitle == jobTitle)&&const DeepCollectionEquality().equals(other._workingDays, _workingDays)&&(identical(other.workStartMinutes, workStartMinutes) || other.workStartMinutes == workStartMinutes)&&(identical(other.workEndMinutes, workEndMinutes) || other.workEndMinutes == workEndMinutes)&&(identical(other.maxJobsPerDay, maxJobsPerDay) || other.maxJobsPerDay == maxJobsPerDay)&&(identical(other.onCall, onCall) || other.onCall == onCall)&&(identical(other.emergencyContact, emergencyContact) || other.emergencyContact == emergencyContact)&&(identical(other.emergencyPhone, emergencyPhone) || other.emergencyPhone == emergencyPhone));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,firstName,lastName,email,phone,color,role,status,uid,jobTitle,const DeepCollectionEquality().hash(_workingDays),workStartMinutes,workEndMinutes,maxJobsPerDay,onCall,emergencyContact,emergencyPhone);

@override
String toString() {
  return 'EmployeeRecord(id: $id, name: $name, firstName: $firstName, lastName: $lastName, email: $email, phone: $phone, color: $color, role: $role, status: $status, uid: $uid, jobTitle: $jobTitle, workingDays: $workingDays, workStartMinutes: $workStartMinutes, workEndMinutes: $workEndMinutes, maxJobsPerDay: $maxJobsPerDay, onCall: $onCall, emergencyContact: $emergencyContact, emergencyPhone: $emergencyPhone)';
}


}

/// @nodoc
abstract mixin class _$EmployeeRecordCopyWith<$Res> implements $EmployeeRecordCopyWith<$Res> {
  factory _$EmployeeRecordCopyWith(_EmployeeRecord value, $Res Function(_EmployeeRecord) _then) = __$EmployeeRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String firstName, String lastName, String email, String phone, Color color, String role, String status, String uid, JobTitle jobTitle, List<bool> workingDays, int workStartMinutes, int workEndMinutes, int maxJobsPerDay, bool onCall, String emergencyContact, String emergencyPhone
});




}
/// @nodoc
class __$EmployeeRecordCopyWithImpl<$Res>
    implements _$EmployeeRecordCopyWith<$Res> {
  __$EmployeeRecordCopyWithImpl(this._self, this._then);

  final _EmployeeRecord _self;
  final $Res Function(_EmployeeRecord) _then;

/// Create a copy of EmployeeRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? firstName = null,Object? lastName = null,Object? email = null,Object? phone = null,Object? color = null,Object? role = null,Object? status = null,Object? uid = null,Object? jobTitle = null,Object? workingDays = null,Object? workStartMinutes = null,Object? workEndMinutes = null,Object? maxJobsPerDay = null,Object? onCall = null,Object? emergencyContact = null,Object? emergencyPhone = null,}) {
  return _then(_EmployeeRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,firstName: null == firstName ? _self.firstName : firstName // ignore: cast_nullable_to_non_nullable
as String,lastName: null == lastName ? _self.lastName : lastName // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as Color,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,jobTitle: null == jobTitle ? _self.jobTitle : jobTitle // ignore: cast_nullable_to_non_nullable
as JobTitle,workingDays: null == workingDays ? _self._workingDays : workingDays // ignore: cast_nullable_to_non_nullable
as List<bool>,workStartMinutes: null == workStartMinutes ? _self.workStartMinutes : workStartMinutes // ignore: cast_nullable_to_non_nullable
as int,workEndMinutes: null == workEndMinutes ? _self.workEndMinutes : workEndMinutes // ignore: cast_nullable_to_non_nullable
as int,maxJobsPerDay: null == maxJobsPerDay ? _self.maxJobsPerDay : maxJobsPerDay // ignore: cast_nullable_to_non_nullable
as int,onCall: null == onCall ? _self.onCall : onCall // ignore: cast_nullable_to_non_nullable
as bool,emergencyContact: null == emergencyContact ? _self.emergencyContact : emergencyContact // ignore: cast_nullable_to_non_nullable
as String,emergencyPhone: null == emergencyPhone ? _self.emergencyPhone : emergencyPhone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
