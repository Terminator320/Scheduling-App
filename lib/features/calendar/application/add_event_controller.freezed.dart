// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'add_event_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AddEventState {

 DateTime? get selectedDate; DateTime? get endDate;/// Whether the end date should move with later start-date changes.
 bool get endDateTouched; TimeOfDay? get selectedStartTime; TimeOfDay? get selectedEndTime; bool get endTimeWasPickedManually;/// Seeded job length; the end follows the start by this many minutes.
 int? get durationMinutes; ClientRecord? get selectedClient; List<ClientRecord> get clientResults; bool get isSearchingClient; ClientSearchStatus get clientSearchStatus; bool get useCustomAddress; bool get isPersonal; bool get isDayOff; bool get isAllDay; List<EmployeeRecord> get selectedEmployees; RepeatInterval get repeat; List<File> get selectedImages; bool get isSubmitting; Map<String, AppointmentFormError> get errors;
/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddEventStateCopyWith<AddEventState> get copyWith => _$AddEventStateCopyWithImpl<AddEventState>(this as AddEventState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AddEventState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddEventState&&(identical(other.selectedDate, _this.selectedDate) || other.selectedDate == _this.selectedDate)&&(identical(other.endDate, _this.endDate) || other.endDate == _this.endDate)&&(identical(other.endDateTouched, _this.endDateTouched) || other.endDateTouched == _this.endDateTouched)&&(identical(other.selectedStartTime, _this.selectedStartTime) || other.selectedStartTime == _this.selectedStartTime)&&(identical(other.selectedEndTime, _this.selectedEndTime) || other.selectedEndTime == _this.selectedEndTime)&&(identical(other.endTimeWasPickedManually, _this.endTimeWasPickedManually) || other.endTimeWasPickedManually == _this.endTimeWasPickedManually)&&(identical(other.durationMinutes, _this.durationMinutes) || other.durationMinutes == _this.durationMinutes)&&(identical(other.selectedClient, _this.selectedClient) || other.selectedClient == _this.selectedClient)&&const DeepCollectionEquality().equals(other.clientResults, _this.clientResults)&&(identical(other.isSearchingClient, _this.isSearchingClient) || other.isSearchingClient == _this.isSearchingClient)&&(identical(other.clientSearchStatus, _this.clientSearchStatus) || other.clientSearchStatus == _this.clientSearchStatus)&&(identical(other.useCustomAddress, _this.useCustomAddress) || other.useCustomAddress == _this.useCustomAddress)&&(identical(other.isPersonal, _this.isPersonal) || other.isPersonal == _this.isPersonal)&&(identical(other.isDayOff, _this.isDayOff) || other.isDayOff == _this.isDayOff)&&(identical(other.isAllDay, _this.isAllDay) || other.isAllDay == _this.isAllDay)&&const DeepCollectionEquality().equals(other.selectedEmployees, _this.selectedEmployees)&&(identical(other.repeat, _this.repeat) || other.repeat == _this.repeat)&&const DeepCollectionEquality().equals(other.selectedImages, _this.selectedImages)&&(identical(other.isSubmitting, _this.isSubmitting) || other.isSubmitting == _this.isSubmitting)&&const DeepCollectionEquality().equals(other.errors, _this.errors));
}


@override
int get hashCode {
  final _this = this as AddEventState;
  return Object.hashAll([runtimeType,_this.selectedDate,_this.endDate,_this.endDateTouched,_this.selectedStartTime,_this.selectedEndTime,_this.endTimeWasPickedManually,_this.durationMinutes,_this.selectedClient,const DeepCollectionEquality().hash(_this.clientResults),_this.isSearchingClient,_this.clientSearchStatus,_this.useCustomAddress,_this.isPersonal,_this.isDayOff,_this.isAllDay,const DeepCollectionEquality().hash(_this.selectedEmployees),_this.repeat,const DeepCollectionEquality().hash(_this.selectedImages),_this.isSubmitting,const DeepCollectionEquality().hash(_this.errors)]);
}

@override
String toString() {
  final _this = this as AddEventState;
  return 'AddEventState(selectedDate: ${_this.selectedDate}, endDate: ${_this.endDate}, endDateTouched: ${_this.endDateTouched}, selectedStartTime: ${_this.selectedStartTime}, selectedEndTime: ${_this.selectedEndTime}, endTimeWasPickedManually: ${_this.endTimeWasPickedManually}, durationMinutes: ${_this.durationMinutes}, selectedClient: ${_this.selectedClient}, clientResults: ${_this.clientResults}, isSearchingClient: ${_this.isSearchingClient}, clientSearchStatus: ${_this.clientSearchStatus}, useCustomAddress: ${_this.useCustomAddress}, isPersonal: ${_this.isPersonal}, isDayOff: ${_this.isDayOff}, isAllDay: ${_this.isAllDay}, selectedEmployees: ${_this.selectedEmployees}, repeat: ${_this.repeat}, selectedImages: ${_this.selectedImages}, isSubmitting: ${_this.isSubmitting}, errors: ${_this.errors})';
}


}

/// @nodoc
abstract mixin class $AddEventStateCopyWith<$Res>  {
  factory $AddEventStateCopyWith(AddEventState value, $Res Function(AddEventState) _then) = _$AddEventStateCopyWithImpl;
@useResult
$Res call({
 DateTime? selectedDate, DateTime? endDate, bool endDateTouched, TimeOfDay? selectedStartTime, TimeOfDay? selectedEndTime, bool endTimeWasPickedManually, int? durationMinutes, ClientRecord? selectedClient, List<ClientRecord> clientResults, bool isSearchingClient, ClientSearchStatus clientSearchStatus, bool useCustomAddress, bool isPersonal, bool isDayOff, bool isAllDay, List<EmployeeRecord> selectedEmployees, RepeatInterval repeat, List<File> selectedImages, bool isSubmitting, Map<String, AppointmentFormError> errors
});


$ClientRecordCopyWith<$Res>? get selectedClient;$ClientSearchStatusCopyWith<$Res> get clientSearchStatus;

}
/// @nodoc
class _$AddEventStateCopyWithImpl<$Res>
    implements $AddEventStateCopyWith<$Res> {
  _$AddEventStateCopyWithImpl(this._self, this._then);

  final AddEventState _self;
  final $Res Function(AddEventState) _then;

/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selectedDate = freezed,Object? endDate = freezed,Object? endDateTouched = null,Object? selectedStartTime = freezed,Object? selectedEndTime = freezed,Object? endTimeWasPickedManually = null,Object? durationMinutes = freezed,Object? selectedClient = freezed,Object? clientResults = null,Object? isSearchingClient = null,Object? clientSearchStatus = null,Object? useCustomAddress = null,Object? isPersonal = null,Object? isDayOff = null,Object? isAllDay = null,Object? selectedEmployees = null,Object? repeat = null,Object? selectedImages = null,Object? isSubmitting = null,Object? errors = null,}) {
  return _then(AddEventState(
selectedDate: freezed == selectedDate ? _self.selectedDate : selectedDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDateTouched: null == endDateTouched ? _self.endDateTouched : endDateTouched // ignore: cast_nullable_to_non_nullable
as bool,selectedStartTime: freezed == selectedStartTime ? _self.selectedStartTime : selectedStartTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay?,selectedEndTime: freezed == selectedEndTime ? _self.selectedEndTime : selectedEndTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay?,endTimeWasPickedManually: null == endTimeWasPickedManually ? _self.endTimeWasPickedManually : endTimeWasPickedManually // ignore: cast_nullable_to_non_nullable
as bool,durationMinutes: freezed == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int?,selectedClient: freezed == selectedClient ? _self.selectedClient : selectedClient // ignore: cast_nullable_to_non_nullable
as ClientRecord?,clientResults: null == clientResults ? _self.clientResults : clientResults // ignore: cast_nullable_to_non_nullable
as List<ClientRecord>,isSearchingClient: null == isSearchingClient ? _self.isSearchingClient : isSearchingClient // ignore: cast_nullable_to_non_nullable
as bool,clientSearchStatus: null == clientSearchStatus ? _self.clientSearchStatus : clientSearchStatus // ignore: cast_nullable_to_non_nullable
as ClientSearchStatus,useCustomAddress: null == useCustomAddress ? _self.useCustomAddress : useCustomAddress // ignore: cast_nullable_to_non_nullable
as bool,isPersonal: null == isPersonal ? _self.isPersonal : isPersonal // ignore: cast_nullable_to_non_nullable
as bool,isDayOff: null == isDayOff ? _self.isDayOff : isDayOff // ignore: cast_nullable_to_non_nullable
as bool,isAllDay: null == isAllDay ? _self.isAllDay : isAllDay // ignore: cast_nullable_to_non_nullable
as bool,selectedEmployees: null == selectedEmployees ? _self.selectedEmployees : selectedEmployees // ignore: cast_nullable_to_non_nullable
as List<EmployeeRecord>,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,selectedImages: null == selectedImages ? _self.selectedImages : selectedImages // ignore: cast_nullable_to_non_nullable
as List<File>,isSubmitting: null == isSubmitting ? _self.isSubmitting : isSubmitting // ignore: cast_nullable_to_non_nullable
as bool,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, AppointmentFormError>,
  ));
}
/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientRecordCopyWith<$Res>? get selectedClient {
    if (_self.selectedClient == null) {
    return null;
  }

  return $ClientRecordCopyWith<$Res>(_self.selectedClient!, (value) {
    return _then(_self.copyWith(selectedClient: value));
  });
}/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientSearchStatusCopyWith<$Res> get clientSearchStatus {
  
  return $ClientSearchStatusCopyWith<$Res>(_self.clientSearchStatus, (value) {
    return _then(_self.copyWith(clientSearchStatus: value));
  });
}
}


/// Adds pattern-matching-related methods to [AddEventState].
extension AddEventStatePatterns on AddEventState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AddEventState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AddEventState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AddEventState value)  $default,){
final _that = this;
switch (_that) {
case _AddEventState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AddEventState value)?  $default,){
final _that = this;
switch (_that) {
case _AddEventState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime? selectedDate,  DateTime? endDate,  bool endDateTouched,  TimeOfDay? selectedStartTime,  TimeOfDay? selectedEndTime,  bool endTimeWasPickedManually,  int? durationMinutes,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  ClientSearchStatus clientSearchStatus,  bool useCustomAddress,  bool isPersonal,  bool isDayOff,  bool isAllDay,  List<EmployeeRecord> selectedEmployees,  RepeatInterval repeat,  List<File> selectedImages,  bool isSubmitting,  Map<String, AppointmentFormError> errors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AddEventState() when $default != null:
return $default(_that.selectedDate,_that.endDate,_that.endDateTouched,_that.selectedStartTime,_that.selectedEndTime,_that.endTimeWasPickedManually,_that.durationMinutes,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.clientSearchStatus,_that.useCustomAddress,_that.isPersonal,_that.isDayOff,_that.isAllDay,_that.selectedEmployees,_that.repeat,_that.selectedImages,_that.isSubmitting,_that.errors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime? selectedDate,  DateTime? endDate,  bool endDateTouched,  TimeOfDay? selectedStartTime,  TimeOfDay? selectedEndTime,  bool endTimeWasPickedManually,  int? durationMinutes,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  ClientSearchStatus clientSearchStatus,  bool useCustomAddress,  bool isPersonal,  bool isDayOff,  bool isAllDay,  List<EmployeeRecord> selectedEmployees,  RepeatInterval repeat,  List<File> selectedImages,  bool isSubmitting,  Map<String, AppointmentFormError> errors)  $default,) {final _that = this;
switch (_that) {
case _AddEventState():
return $default(_that.selectedDate,_that.endDate,_that.endDateTouched,_that.selectedStartTime,_that.selectedEndTime,_that.endTimeWasPickedManually,_that.durationMinutes,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.clientSearchStatus,_that.useCustomAddress,_that.isPersonal,_that.isDayOff,_that.isAllDay,_that.selectedEmployees,_that.repeat,_that.selectedImages,_that.isSubmitting,_that.errors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime? selectedDate,  DateTime? endDate,  bool endDateTouched,  TimeOfDay? selectedStartTime,  TimeOfDay? selectedEndTime,  bool endTimeWasPickedManually,  int? durationMinutes,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  ClientSearchStatus clientSearchStatus,  bool useCustomAddress,  bool isPersonal,  bool isDayOff,  bool isAllDay,  List<EmployeeRecord> selectedEmployees,  RepeatInterval repeat,  List<File> selectedImages,  bool isSubmitting,  Map<String, AppointmentFormError> errors)?  $default,) {final _that = this;
switch (_that) {
case _AddEventState() when $default != null:
return $default(_that.selectedDate,_that.endDate,_that.endDateTouched,_that.selectedStartTime,_that.selectedEndTime,_that.endTimeWasPickedManually,_that.durationMinutes,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.clientSearchStatus,_that.useCustomAddress,_that.isPersonal,_that.isDayOff,_that.isAllDay,_that.selectedEmployees,_that.repeat,_that.selectedImages,_that.isSubmitting,_that.errors);case _:
  return null;

}
}

}

/// @nodoc


class _AddEventState implements AddEventState {
  const _AddEventState({this.selectedDate, this.endDate, this.endDateTouched = false, this.selectedStartTime, this.selectedEndTime, this.endTimeWasPickedManually = false, this.durationMinutes, this.selectedClient,  List<ClientRecord> clientResults = const <ClientRecord>[], this.isSearchingClient = false, this.clientSearchStatus = const ClientSearchStatus(), this.useCustomAddress = false, this.isPersonal = false, this.isDayOff = false, this.isAllDay = false,  List<EmployeeRecord> selectedEmployees = const <EmployeeRecord>[], this.repeat = RepeatInterval.none,  List<File> selectedImages = const <File>[], this.isSubmitting = false,  Map<String, AppointmentFormError> errors = const <String, AppointmentFormError>{}}): _clientResults = clientResults,_selectedEmployees = selectedEmployees,_selectedImages = selectedImages,_errors = errors;
  

@override final  DateTime? selectedDate;
@override final  DateTime? endDate;
/// Whether the end date should move with later start-date changes.
@override@JsonKey() final  bool endDateTouched;
@override final  TimeOfDay? selectedStartTime;
@override final  TimeOfDay? selectedEndTime;
@override@JsonKey() final  bool endTimeWasPickedManually;
/// Seeded job length; the end follows the start by this many minutes.
@override final  int? durationMinutes;
@override final  ClientRecord? selectedClient;
 final  List<ClientRecord> _clientResults;
@override@JsonKey() List<ClientRecord> get clientResults {
  if (_clientResults is EqualUnmodifiableListView) return _clientResults;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_clientResults);
}

@override@JsonKey() final  bool isSearchingClient;
@override@JsonKey() final  ClientSearchStatus clientSearchStatus;
@override@JsonKey() final  bool useCustomAddress;
@override@JsonKey() final  bool isPersonal;
@override@JsonKey() final  bool isDayOff;
@override@JsonKey() final  bool isAllDay;
 final  List<EmployeeRecord> _selectedEmployees;
@override@JsonKey() List<EmployeeRecord> get selectedEmployees {
  if (_selectedEmployees is EqualUnmodifiableListView) return _selectedEmployees;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedEmployees);
}

@override@JsonKey() final  RepeatInterval repeat;
 final  List<File> _selectedImages;
@override@JsonKey() List<File> get selectedImages {
  if (_selectedImages is EqualUnmodifiableListView) return _selectedImages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedImages);
}

@override@JsonKey() final  bool isSubmitting;
 final  Map<String, AppointmentFormError> _errors;
@override@JsonKey() Map<String, AppointmentFormError> get errors {
  if (_errors is EqualUnmodifiableMapView) return _errors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_errors);
}


/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddEventStateCopyWith<_AddEventState> get copyWith => __$AddEventStateCopyWithImpl<_AddEventState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AddEventState&&(identical(other.selectedDate, selectedDate) || other.selectedDate == selectedDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.endDateTouched, endDateTouched) || other.endDateTouched == endDateTouched)&&(identical(other.selectedStartTime, selectedStartTime) || other.selectedStartTime == selectedStartTime)&&(identical(other.selectedEndTime, selectedEndTime) || other.selectedEndTime == selectedEndTime)&&(identical(other.endTimeWasPickedManually, endTimeWasPickedManually) || other.endTimeWasPickedManually == endTimeWasPickedManually)&&(identical(other.durationMinutes, durationMinutes) || other.durationMinutes == durationMinutes)&&(identical(other.selectedClient, selectedClient) || other.selectedClient == selectedClient)&&const DeepCollectionEquality().equals(other.clientResults, _clientResults)&&(identical(other.isSearchingClient, isSearchingClient) || other.isSearchingClient == isSearchingClient)&&(identical(other.clientSearchStatus, clientSearchStatus) || other.clientSearchStatus == clientSearchStatus)&&(identical(other.useCustomAddress, useCustomAddress) || other.useCustomAddress == useCustomAddress)&&(identical(other.isPersonal, isPersonal) || other.isPersonal == isPersonal)&&(identical(other.isDayOff, isDayOff) || other.isDayOff == isDayOff)&&(identical(other.isAllDay, isAllDay) || other.isAllDay == isAllDay)&&const DeepCollectionEquality().equals(other.selectedEmployees, _selectedEmployees)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&const DeepCollectionEquality().equals(other.selectedImages, _selectedImages)&&(identical(other.isSubmitting, isSubmitting) || other.isSubmitting == isSubmitting)&&const DeepCollectionEquality().equals(other.errors, _errors));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,selectedDate,endDate,endDateTouched,selectedStartTime,selectedEndTime,endTimeWasPickedManually,durationMinutes,selectedClient,const DeepCollectionEquality().hash(_clientResults),isSearchingClient,clientSearchStatus,useCustomAddress,isPersonal,isDayOff,isAllDay,const DeepCollectionEquality().hash(_selectedEmployees),repeat,const DeepCollectionEquality().hash(_selectedImages),isSubmitting,const DeepCollectionEquality().hash(_errors)]);
}

@override
String toString() {
    return 'AddEventState(selectedDate: $selectedDate, endDate: $endDate, endDateTouched: $endDateTouched, selectedStartTime: $selectedStartTime, selectedEndTime: $selectedEndTime, endTimeWasPickedManually: $endTimeWasPickedManually, durationMinutes: $durationMinutes, selectedClient: $selectedClient, clientResults: $clientResults, isSearchingClient: $isSearchingClient, clientSearchStatus: $clientSearchStatus, useCustomAddress: $useCustomAddress, isPersonal: $isPersonal, isDayOff: $isDayOff, isAllDay: $isAllDay, selectedEmployees: $selectedEmployees, repeat: $repeat, selectedImages: $selectedImages, isSubmitting: $isSubmitting, errors: $errors)';
}


}

/// @nodoc
abstract mixin class _$AddEventStateCopyWith<$Res> implements $AddEventStateCopyWith<$Res> {
  factory _$AddEventStateCopyWith(_AddEventState value, $Res Function(_AddEventState) _then) = __$AddEventStateCopyWithImpl;
@override @useResult
$Res call({
 DateTime? selectedDate, DateTime? endDate, bool endDateTouched, TimeOfDay? selectedStartTime, TimeOfDay? selectedEndTime, bool endTimeWasPickedManually, int? durationMinutes, ClientRecord? selectedClient, List<ClientRecord> clientResults, bool isSearchingClient, ClientSearchStatus clientSearchStatus, bool useCustomAddress, bool isPersonal, bool isDayOff, bool isAllDay, List<EmployeeRecord> selectedEmployees, RepeatInterval repeat, List<File> selectedImages, bool isSubmitting, Map<String, AppointmentFormError> errors
});


@override $ClientRecordCopyWith<$Res>? get selectedClient;@override $ClientSearchStatusCopyWith<$Res> get clientSearchStatus;

}
/// @nodoc
class __$AddEventStateCopyWithImpl<$Res>
    implements _$AddEventStateCopyWith<$Res> {
  __$AddEventStateCopyWithImpl(this._self, this._then);

  final _AddEventState _self;
  final $Res Function(_AddEventState) _then;

/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selectedDate = freezed,Object? endDate = freezed,Object? endDateTouched = null,Object? selectedStartTime = freezed,Object? selectedEndTime = freezed,Object? endTimeWasPickedManually = null,Object? durationMinutes = freezed,Object? selectedClient = freezed,Object? clientResults = null,Object? isSearchingClient = null,Object? clientSearchStatus = null,Object? useCustomAddress = null,Object? isPersonal = null,Object? isDayOff = null,Object? isAllDay = null,Object? selectedEmployees = null,Object? repeat = null,Object? selectedImages = null,Object? isSubmitting = null,Object? errors = null,}) {
  return _then(_AddEventState(
selectedDate: freezed == selectedDate ? _self.selectedDate : selectedDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDateTouched: null == endDateTouched ? _self.endDateTouched : endDateTouched // ignore: cast_nullable_to_non_nullable
as bool,selectedStartTime: freezed == selectedStartTime ? _self.selectedStartTime : selectedStartTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay?,selectedEndTime: freezed == selectedEndTime ? _self.selectedEndTime : selectedEndTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay?,endTimeWasPickedManually: null == endTimeWasPickedManually ? _self.endTimeWasPickedManually : endTimeWasPickedManually // ignore: cast_nullable_to_non_nullable
as bool,durationMinutes: freezed == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int?,selectedClient: freezed == selectedClient ? _self.selectedClient : selectedClient // ignore: cast_nullable_to_non_nullable
as ClientRecord?,clientResults: null == clientResults ? _self._clientResults : clientResults // ignore: cast_nullable_to_non_nullable
as List<ClientRecord>,isSearchingClient: null == isSearchingClient ? _self.isSearchingClient : isSearchingClient // ignore: cast_nullable_to_non_nullable
as bool,clientSearchStatus: null == clientSearchStatus ? _self.clientSearchStatus : clientSearchStatus // ignore: cast_nullable_to_non_nullable
as ClientSearchStatus,useCustomAddress: null == useCustomAddress ? _self.useCustomAddress : useCustomAddress // ignore: cast_nullable_to_non_nullable
as bool,isPersonal: null == isPersonal ? _self.isPersonal : isPersonal // ignore: cast_nullable_to_non_nullable
as bool,isDayOff: null == isDayOff ? _self.isDayOff : isDayOff // ignore: cast_nullable_to_non_nullable
as bool,isAllDay: null == isAllDay ? _self.isAllDay : isAllDay // ignore: cast_nullable_to_non_nullable
as bool,selectedEmployees: null == selectedEmployees ? _self._selectedEmployees : selectedEmployees // ignore: cast_nullable_to_non_nullable
as List<EmployeeRecord>,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,selectedImages: null == selectedImages ? _self._selectedImages : selectedImages // ignore: cast_nullable_to_non_nullable
as List<File>,isSubmitting: null == isSubmitting ? _self.isSubmitting : isSubmitting // ignore: cast_nullable_to_non_nullable
as bool,errors: null == errors ? _self._errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, AppointmentFormError>,
  ));
}

/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientRecordCopyWith<$Res>? get selectedClient {
    if (_self.selectedClient == null) {
    return null;
  }

  return $ClientRecordCopyWith<$Res>(_self.selectedClient!, (value) {
    return _then(_self.copyWith(selectedClient: value));
  });
}/// Create a copy of AddEventState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientSearchStatusCopyWith<$Res> get clientSearchStatus {
  
  return $ClientSearchStatusCopyWith<$Res>(_self.clientSearchStatus, (value) {
    return _then(_self.copyWith(clientSearchStatus: value));
  });
}
}

// dart format on
