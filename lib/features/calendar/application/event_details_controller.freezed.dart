// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'event_details_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EventDetailsState {

 DateTime get selectedDate; DateTime get endDate; TimeOfDay get selectedStartTime; TimeOfDay get selectedEndTime; String get editingStatus; bool get isEditing;/// Existing appointments preserve run length when the start date moves.
 bool get endDateTouched; RepeatInterval get repeat; RepeatInterval get savedRepeat; List<EmployeeRecord> get selectedEmployees; List<AppointmentImage> get existingImages; List<AppointmentImage> get removedExistingImages; List<File> get newImages; bool get isSaving; ClientRecord? get client; ClientRecord? get selectedClient; List<ClientRecord> get clientResults; bool get isSearchingClient; bool get useCustomAddress; bool get isPersonal; bool get isDayOff; bool get isAllDay; bool get clientCleared; Map<String, AppointmentFormError> get errors;
/// Create a copy of EventDetailsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventDetailsStateCopyWith<EventDetailsState> get copyWith => _$EventDetailsStateCopyWithImpl<EventDetailsState>(this as EventDetailsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as EventDetailsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventDetailsState&&(identical(other.selectedDate, _this.selectedDate) || other.selectedDate == _this.selectedDate)&&(identical(other.endDate, _this.endDate) || other.endDate == _this.endDate)&&(identical(other.selectedStartTime, _this.selectedStartTime) || other.selectedStartTime == _this.selectedStartTime)&&(identical(other.selectedEndTime, _this.selectedEndTime) || other.selectedEndTime == _this.selectedEndTime)&&(identical(other.editingStatus, _this.editingStatus) || other.editingStatus == _this.editingStatus)&&(identical(other.isEditing, _this.isEditing) || other.isEditing == _this.isEditing)&&(identical(other.endDateTouched, _this.endDateTouched) || other.endDateTouched == _this.endDateTouched)&&(identical(other.repeat, _this.repeat) || other.repeat == _this.repeat)&&(identical(other.savedRepeat, _this.savedRepeat) || other.savedRepeat == _this.savedRepeat)&&const DeepCollectionEquality().equals(other.selectedEmployees, _this.selectedEmployees)&&const DeepCollectionEquality().equals(other.existingImages, _this.existingImages)&&const DeepCollectionEquality().equals(other.removedExistingImages, _this.removedExistingImages)&&const DeepCollectionEquality().equals(other.newImages, _this.newImages)&&(identical(other.isSaving, _this.isSaving) || other.isSaving == _this.isSaving)&&(identical(other.client, _this.client) || other.client == _this.client)&&(identical(other.selectedClient, _this.selectedClient) || other.selectedClient == _this.selectedClient)&&const DeepCollectionEquality().equals(other.clientResults, _this.clientResults)&&(identical(other.isSearchingClient, _this.isSearchingClient) || other.isSearchingClient == _this.isSearchingClient)&&(identical(other.useCustomAddress, _this.useCustomAddress) || other.useCustomAddress == _this.useCustomAddress)&&(identical(other.isPersonal, _this.isPersonal) || other.isPersonal == _this.isPersonal)&&(identical(other.isDayOff, _this.isDayOff) || other.isDayOff == _this.isDayOff)&&(identical(other.isAllDay, _this.isAllDay) || other.isAllDay == _this.isAllDay)&&(identical(other.clientCleared, _this.clientCleared) || other.clientCleared == _this.clientCleared)&&const DeepCollectionEquality().equals(other.errors, _this.errors));
}


@override
int get hashCode {
  final _this = this as EventDetailsState;
  return Object.hashAll([runtimeType,_this.selectedDate,_this.endDate,_this.selectedStartTime,_this.selectedEndTime,_this.editingStatus,_this.isEditing,_this.endDateTouched,_this.repeat,_this.savedRepeat,const DeepCollectionEquality().hash(_this.selectedEmployees),const DeepCollectionEquality().hash(_this.existingImages),const DeepCollectionEquality().hash(_this.removedExistingImages),const DeepCollectionEquality().hash(_this.newImages),_this.isSaving,_this.client,_this.selectedClient,const DeepCollectionEquality().hash(_this.clientResults),_this.isSearchingClient,_this.useCustomAddress,_this.isPersonal,_this.isDayOff,_this.isAllDay,_this.clientCleared,const DeepCollectionEquality().hash(_this.errors)]);
}

@override
String toString() {
  final _this = this as EventDetailsState;
  return 'EventDetailsState(selectedDate: ${_this.selectedDate}, endDate: ${_this.endDate}, selectedStartTime: ${_this.selectedStartTime}, selectedEndTime: ${_this.selectedEndTime}, editingStatus: ${_this.editingStatus}, isEditing: ${_this.isEditing}, endDateTouched: ${_this.endDateTouched}, repeat: ${_this.repeat}, savedRepeat: ${_this.savedRepeat}, selectedEmployees: ${_this.selectedEmployees}, existingImages: ${_this.existingImages}, removedExistingImages: ${_this.removedExistingImages}, newImages: ${_this.newImages}, isSaving: ${_this.isSaving}, client: ${_this.client}, selectedClient: ${_this.selectedClient}, clientResults: ${_this.clientResults}, isSearchingClient: ${_this.isSearchingClient}, useCustomAddress: ${_this.useCustomAddress}, isPersonal: ${_this.isPersonal}, isDayOff: ${_this.isDayOff}, isAllDay: ${_this.isAllDay}, clientCleared: ${_this.clientCleared}, errors: ${_this.errors})';
}


}

/// @nodoc
abstract mixin class $EventDetailsStateCopyWith<$Res>  {
  factory $EventDetailsStateCopyWith(EventDetailsState value, $Res Function(EventDetailsState) _then) = _$EventDetailsStateCopyWithImpl;
@useResult
$Res call({
 DateTime selectedDate, DateTime endDate, TimeOfDay selectedStartTime, TimeOfDay selectedEndTime, String editingStatus, bool isEditing, bool endDateTouched, RepeatInterval repeat, RepeatInterval savedRepeat, List<EmployeeRecord> selectedEmployees, List<AppointmentImage> existingImages, List<AppointmentImage> removedExistingImages, List<File> newImages, bool isSaving, ClientRecord? client, ClientRecord? selectedClient, List<ClientRecord> clientResults, bool isSearchingClient, bool useCustomAddress, bool isPersonal, bool isDayOff, bool isAllDay, bool clientCleared, Map<String, AppointmentFormError> errors
});


$ClientRecordCopyWith<$Res>? get client;$ClientRecordCopyWith<$Res>? get selectedClient;

}
/// @nodoc
class _$EventDetailsStateCopyWithImpl<$Res>
    implements $EventDetailsStateCopyWith<$Res> {
  _$EventDetailsStateCopyWithImpl(this._self, this._then);

  final EventDetailsState _self;
  final $Res Function(EventDetailsState) _then;

/// Create a copy of EventDetailsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selectedDate = null,Object? endDate = null,Object? selectedStartTime = null,Object? selectedEndTime = null,Object? editingStatus = null,Object? isEditing = null,Object? endDateTouched = null,Object? repeat = null,Object? savedRepeat = null,Object? selectedEmployees = null,Object? existingImages = null,Object? removedExistingImages = null,Object? newImages = null,Object? isSaving = null,Object? client = freezed,Object? selectedClient = freezed,Object? clientResults = null,Object? isSearchingClient = null,Object? useCustomAddress = null,Object? isPersonal = null,Object? isDayOff = null,Object? isAllDay = null,Object? clientCleared = null,Object? errors = null,}) {
  return _then(EventDetailsState(
selectedDate: null == selectedDate ? _self.selectedDate : selectedDate // ignore: cast_nullable_to_non_nullable
as DateTime,endDate: null == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime,selectedStartTime: null == selectedStartTime ? _self.selectedStartTime : selectedStartTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay,selectedEndTime: null == selectedEndTime ? _self.selectedEndTime : selectedEndTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay,editingStatus: null == editingStatus ? _self.editingStatus : editingStatus // ignore: cast_nullable_to_non_nullable
as String,isEditing: null == isEditing ? _self.isEditing : isEditing // ignore: cast_nullable_to_non_nullable
as bool,endDateTouched: null == endDateTouched ? _self.endDateTouched : endDateTouched // ignore: cast_nullable_to_non_nullable
as bool,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,savedRepeat: null == savedRepeat ? _self.savedRepeat : savedRepeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,selectedEmployees: null == selectedEmployees ? _self.selectedEmployees : selectedEmployees // ignore: cast_nullable_to_non_nullable
as List<EmployeeRecord>,existingImages: null == existingImages ? _self.existingImages : existingImages // ignore: cast_nullable_to_non_nullable
as List<AppointmentImage>,removedExistingImages: null == removedExistingImages ? _self.removedExistingImages : removedExistingImages // ignore: cast_nullable_to_non_nullable
as List<AppointmentImage>,newImages: null == newImages ? _self.newImages : newImages // ignore: cast_nullable_to_non_nullable
as List<File>,isSaving: null == isSaving ? _self.isSaving : isSaving // ignore: cast_nullable_to_non_nullable
as bool,client: freezed == client ? _self.client : client // ignore: cast_nullable_to_non_nullable
as ClientRecord?,selectedClient: freezed == selectedClient ? _self.selectedClient : selectedClient // ignore: cast_nullable_to_non_nullable
as ClientRecord?,clientResults: null == clientResults ? _self.clientResults : clientResults // ignore: cast_nullable_to_non_nullable
as List<ClientRecord>,isSearchingClient: null == isSearchingClient ? _self.isSearchingClient : isSearchingClient // ignore: cast_nullable_to_non_nullable
as bool,useCustomAddress: null == useCustomAddress ? _self.useCustomAddress : useCustomAddress // ignore: cast_nullable_to_non_nullable
as bool,isPersonal: null == isPersonal ? _self.isPersonal : isPersonal // ignore: cast_nullable_to_non_nullable
as bool,isDayOff: null == isDayOff ? _self.isDayOff : isDayOff // ignore: cast_nullable_to_non_nullable
as bool,isAllDay: null == isAllDay ? _self.isAllDay : isAllDay // ignore: cast_nullable_to_non_nullable
as bool,clientCleared: null == clientCleared ? _self.clientCleared : clientCleared // ignore: cast_nullable_to_non_nullable
as bool,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, AppointmentFormError>,
  ));
}
/// Create a copy of EventDetailsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientRecordCopyWith<$Res>? get client {
    if (_self.client == null) {
    return null;
  }

  return $ClientRecordCopyWith<$Res>(_self.client!, (value) {
    return _then(_self.copyWith(client: value));
  });
}/// Create a copy of EventDetailsState
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
}
}


/// Adds pattern-matching-related methods to [EventDetailsState].
extension EventDetailsStatePatterns on EventDetailsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EventDetailsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EventDetailsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EventDetailsState value)  $default,){
final _that = this;
switch (_that) {
case _EventDetailsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EventDetailsState value)?  $default,){
final _that = this;
switch (_that) {
case _EventDetailsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime selectedDate,  DateTime endDate,  TimeOfDay selectedStartTime,  TimeOfDay selectedEndTime,  String editingStatus,  bool isEditing,  bool endDateTouched,  RepeatInterval repeat,  RepeatInterval savedRepeat,  List<EmployeeRecord> selectedEmployees,  List<AppointmentImage> existingImages,  List<AppointmentImage> removedExistingImages,  List<File> newImages,  bool isSaving,  ClientRecord? client,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  bool useCustomAddress,  bool isPersonal,  bool isDayOff,  bool isAllDay,  bool clientCleared,  Map<String, AppointmentFormError> errors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EventDetailsState() when $default != null:
return $default(_that.selectedDate,_that.endDate,_that.selectedStartTime,_that.selectedEndTime,_that.editingStatus,_that.isEditing,_that.endDateTouched,_that.repeat,_that.savedRepeat,_that.selectedEmployees,_that.existingImages,_that.removedExistingImages,_that.newImages,_that.isSaving,_that.client,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.useCustomAddress,_that.isPersonal,_that.isDayOff,_that.isAllDay,_that.clientCleared,_that.errors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime selectedDate,  DateTime endDate,  TimeOfDay selectedStartTime,  TimeOfDay selectedEndTime,  String editingStatus,  bool isEditing,  bool endDateTouched,  RepeatInterval repeat,  RepeatInterval savedRepeat,  List<EmployeeRecord> selectedEmployees,  List<AppointmentImage> existingImages,  List<AppointmentImage> removedExistingImages,  List<File> newImages,  bool isSaving,  ClientRecord? client,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  bool useCustomAddress,  bool isPersonal,  bool isDayOff,  bool isAllDay,  bool clientCleared,  Map<String, AppointmentFormError> errors)  $default,) {final _that = this;
switch (_that) {
case _EventDetailsState():
return $default(_that.selectedDate,_that.endDate,_that.selectedStartTime,_that.selectedEndTime,_that.editingStatus,_that.isEditing,_that.endDateTouched,_that.repeat,_that.savedRepeat,_that.selectedEmployees,_that.existingImages,_that.removedExistingImages,_that.newImages,_that.isSaving,_that.client,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.useCustomAddress,_that.isPersonal,_that.isDayOff,_that.isAllDay,_that.clientCleared,_that.errors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime selectedDate,  DateTime endDate,  TimeOfDay selectedStartTime,  TimeOfDay selectedEndTime,  String editingStatus,  bool isEditing,  bool endDateTouched,  RepeatInterval repeat,  RepeatInterval savedRepeat,  List<EmployeeRecord> selectedEmployees,  List<AppointmentImage> existingImages,  List<AppointmentImage> removedExistingImages,  List<File> newImages,  bool isSaving,  ClientRecord? client,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  bool useCustomAddress,  bool isPersonal,  bool isDayOff,  bool isAllDay,  bool clientCleared,  Map<String, AppointmentFormError> errors)?  $default,) {final _that = this;
switch (_that) {
case _EventDetailsState() when $default != null:
return $default(_that.selectedDate,_that.endDate,_that.selectedStartTime,_that.selectedEndTime,_that.editingStatus,_that.isEditing,_that.endDateTouched,_that.repeat,_that.savedRepeat,_that.selectedEmployees,_that.existingImages,_that.removedExistingImages,_that.newImages,_that.isSaving,_that.client,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.useCustomAddress,_that.isPersonal,_that.isDayOff,_that.isAllDay,_that.clientCleared,_that.errors);case _:
  return null;

}
}

}

/// @nodoc


class _EventDetailsState implements EventDetailsState {
  const _EventDetailsState({required this.selectedDate, required this.endDate, required this.selectedStartTime, required this.selectedEndTime, required this.editingStatus, this.isEditing = false, this.endDateTouched = true, this.repeat = RepeatInterval.none, this.savedRepeat = RepeatInterval.none,  List<EmployeeRecord> selectedEmployees = const <EmployeeRecord>[],  List<AppointmentImage> existingImages = const <AppointmentImage>[],  List<AppointmentImage> removedExistingImages = const <AppointmentImage>[],  List<File> newImages = const <File>[], this.isSaving = false, this.client, this.selectedClient,  List<ClientRecord> clientResults = const <ClientRecord>[], this.isSearchingClient = false, this.useCustomAddress = false, this.isPersonal = false, this.isDayOff = false, this.isAllDay = false, this.clientCleared = false,  Map<String, AppointmentFormError> errors = const <String, AppointmentFormError>{}}): _selectedEmployees = selectedEmployees,_existingImages = existingImages,_removedExistingImages = removedExistingImages,_newImages = newImages,_clientResults = clientResults,_errors = errors;
  

@override final  DateTime selectedDate;
@override final  DateTime endDate;
@override final  TimeOfDay selectedStartTime;
@override final  TimeOfDay selectedEndTime;
@override final  String editingStatus;
@override@JsonKey() final  bool isEditing;
/// Existing appointments preserve run length when the start date moves.
@override@JsonKey() final  bool endDateTouched;
@override@JsonKey() final  RepeatInterval repeat;
@override@JsonKey() final  RepeatInterval savedRepeat;
 final  List<EmployeeRecord> _selectedEmployees;
@override@JsonKey() List<EmployeeRecord> get selectedEmployees {
  if (_selectedEmployees is EqualUnmodifiableListView) return _selectedEmployees;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedEmployees);
}

 final  List<AppointmentImage> _existingImages;
@override@JsonKey() List<AppointmentImage> get existingImages {
  if (_existingImages is EqualUnmodifiableListView) return _existingImages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_existingImages);
}

 final  List<AppointmentImage> _removedExistingImages;
@override@JsonKey() List<AppointmentImage> get removedExistingImages {
  if (_removedExistingImages is EqualUnmodifiableListView) return _removedExistingImages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_removedExistingImages);
}

 final  List<File> _newImages;
@override@JsonKey() List<File> get newImages {
  if (_newImages is EqualUnmodifiableListView) return _newImages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_newImages);
}

@override@JsonKey() final  bool isSaving;
@override final  ClientRecord? client;
@override final  ClientRecord? selectedClient;
 final  List<ClientRecord> _clientResults;
@override@JsonKey() List<ClientRecord> get clientResults {
  if (_clientResults is EqualUnmodifiableListView) return _clientResults;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_clientResults);
}

@override@JsonKey() final  bool isSearchingClient;
@override@JsonKey() final  bool useCustomAddress;
@override@JsonKey() final  bool isPersonal;
@override@JsonKey() final  bool isDayOff;
@override@JsonKey() final  bool isAllDay;
@override@JsonKey() final  bool clientCleared;
 final  Map<String, AppointmentFormError> _errors;
@override@JsonKey() Map<String, AppointmentFormError> get errors {
  if (_errors is EqualUnmodifiableMapView) return _errors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_errors);
}


/// Create a copy of EventDetailsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EventDetailsStateCopyWith<_EventDetailsState> get copyWith => __$EventDetailsStateCopyWithImpl<_EventDetailsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EventDetailsState&&(identical(other.selectedDate, selectedDate) || other.selectedDate == selectedDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.selectedStartTime, selectedStartTime) || other.selectedStartTime == selectedStartTime)&&(identical(other.selectedEndTime, selectedEndTime) || other.selectedEndTime == selectedEndTime)&&(identical(other.editingStatus, editingStatus) || other.editingStatus == editingStatus)&&(identical(other.isEditing, isEditing) || other.isEditing == isEditing)&&(identical(other.endDateTouched, endDateTouched) || other.endDateTouched == endDateTouched)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.savedRepeat, savedRepeat) || other.savedRepeat == savedRepeat)&&const DeepCollectionEquality().equals(other.selectedEmployees, _selectedEmployees)&&const DeepCollectionEquality().equals(other.existingImages, _existingImages)&&const DeepCollectionEquality().equals(other.removedExistingImages, _removedExistingImages)&&const DeepCollectionEquality().equals(other.newImages, _newImages)&&(identical(other.isSaving, isSaving) || other.isSaving == isSaving)&&(identical(other.client, client) || other.client == client)&&(identical(other.selectedClient, selectedClient) || other.selectedClient == selectedClient)&&const DeepCollectionEquality().equals(other.clientResults, _clientResults)&&(identical(other.isSearchingClient, isSearchingClient) || other.isSearchingClient == isSearchingClient)&&(identical(other.useCustomAddress, useCustomAddress) || other.useCustomAddress == useCustomAddress)&&(identical(other.isPersonal, isPersonal) || other.isPersonal == isPersonal)&&(identical(other.isDayOff, isDayOff) || other.isDayOff == isDayOff)&&(identical(other.isAllDay, isAllDay) || other.isAllDay == isAllDay)&&(identical(other.clientCleared, clientCleared) || other.clientCleared == clientCleared)&&const DeepCollectionEquality().equals(other.errors, _errors));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,selectedDate,endDate,selectedStartTime,selectedEndTime,editingStatus,isEditing,endDateTouched,repeat,savedRepeat,const DeepCollectionEquality().hash(_selectedEmployees),const DeepCollectionEquality().hash(_existingImages),const DeepCollectionEquality().hash(_removedExistingImages),const DeepCollectionEquality().hash(_newImages),isSaving,client,selectedClient,const DeepCollectionEquality().hash(_clientResults),isSearchingClient,useCustomAddress,isPersonal,isDayOff,isAllDay,clientCleared,const DeepCollectionEquality().hash(_errors)]);
}

@override
String toString() {
    return 'EventDetailsState(selectedDate: $selectedDate, endDate: $endDate, selectedStartTime: $selectedStartTime, selectedEndTime: $selectedEndTime, editingStatus: $editingStatus, isEditing: $isEditing, endDateTouched: $endDateTouched, repeat: $repeat, savedRepeat: $savedRepeat, selectedEmployees: $selectedEmployees, existingImages: $existingImages, removedExistingImages: $removedExistingImages, newImages: $newImages, isSaving: $isSaving, client: $client, selectedClient: $selectedClient, clientResults: $clientResults, isSearchingClient: $isSearchingClient, useCustomAddress: $useCustomAddress, isPersonal: $isPersonal, isDayOff: $isDayOff, isAllDay: $isAllDay, clientCleared: $clientCleared, errors: $errors)';
}


}

/// @nodoc
abstract mixin class _$EventDetailsStateCopyWith<$Res> implements $EventDetailsStateCopyWith<$Res> {
  factory _$EventDetailsStateCopyWith(_EventDetailsState value, $Res Function(_EventDetailsState) _then) = __$EventDetailsStateCopyWithImpl;
@override @useResult
$Res call({
 DateTime selectedDate, DateTime endDate, TimeOfDay selectedStartTime, TimeOfDay selectedEndTime, String editingStatus, bool isEditing, bool endDateTouched, RepeatInterval repeat, RepeatInterval savedRepeat, List<EmployeeRecord> selectedEmployees, List<AppointmentImage> existingImages, List<AppointmentImage> removedExistingImages, List<File> newImages, bool isSaving, ClientRecord? client, ClientRecord? selectedClient, List<ClientRecord> clientResults, bool isSearchingClient, bool useCustomAddress, bool isPersonal, bool isDayOff, bool isAllDay, bool clientCleared, Map<String, AppointmentFormError> errors
});


@override $ClientRecordCopyWith<$Res>? get client;@override $ClientRecordCopyWith<$Res>? get selectedClient;

}
/// @nodoc
class __$EventDetailsStateCopyWithImpl<$Res>
    implements _$EventDetailsStateCopyWith<$Res> {
  __$EventDetailsStateCopyWithImpl(this._self, this._then);

  final _EventDetailsState _self;
  final $Res Function(_EventDetailsState) _then;

/// Create a copy of EventDetailsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selectedDate = null,Object? endDate = null,Object? selectedStartTime = null,Object? selectedEndTime = null,Object? editingStatus = null,Object? isEditing = null,Object? endDateTouched = null,Object? repeat = null,Object? savedRepeat = null,Object? selectedEmployees = null,Object? existingImages = null,Object? removedExistingImages = null,Object? newImages = null,Object? isSaving = null,Object? client = freezed,Object? selectedClient = freezed,Object? clientResults = null,Object? isSearchingClient = null,Object? useCustomAddress = null,Object? isPersonal = null,Object? isDayOff = null,Object? isAllDay = null,Object? clientCleared = null,Object? errors = null,}) {
  return _then(_EventDetailsState(
selectedDate: null == selectedDate ? _self.selectedDate : selectedDate // ignore: cast_nullable_to_non_nullable
as DateTime,endDate: null == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime,selectedStartTime: null == selectedStartTime ? _self.selectedStartTime : selectedStartTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay,selectedEndTime: null == selectedEndTime ? _self.selectedEndTime : selectedEndTime // ignore: cast_nullable_to_non_nullable
as TimeOfDay,editingStatus: null == editingStatus ? _self.editingStatus : editingStatus // ignore: cast_nullable_to_non_nullable
as String,isEditing: null == isEditing ? _self.isEditing : isEditing // ignore: cast_nullable_to_non_nullable
as bool,endDateTouched: null == endDateTouched ? _self.endDateTouched : endDateTouched // ignore: cast_nullable_to_non_nullable
as bool,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,savedRepeat: null == savedRepeat ? _self.savedRepeat : savedRepeat // ignore: cast_nullable_to_non_nullable
as RepeatInterval,selectedEmployees: null == selectedEmployees ? _self._selectedEmployees : selectedEmployees // ignore: cast_nullable_to_non_nullable
as List<EmployeeRecord>,existingImages: null == existingImages ? _self._existingImages : existingImages // ignore: cast_nullable_to_non_nullable
as List<AppointmentImage>,removedExistingImages: null == removedExistingImages ? _self._removedExistingImages : removedExistingImages // ignore: cast_nullable_to_non_nullable
as List<AppointmentImage>,newImages: null == newImages ? _self._newImages : newImages // ignore: cast_nullable_to_non_nullable
as List<File>,isSaving: null == isSaving ? _self.isSaving : isSaving // ignore: cast_nullable_to_non_nullable
as bool,client: freezed == client ? _self.client : client // ignore: cast_nullable_to_non_nullable
as ClientRecord?,selectedClient: freezed == selectedClient ? _self.selectedClient : selectedClient // ignore: cast_nullable_to_non_nullable
as ClientRecord?,clientResults: null == clientResults ? _self._clientResults : clientResults // ignore: cast_nullable_to_non_nullable
as List<ClientRecord>,isSearchingClient: null == isSearchingClient ? _self.isSearchingClient : isSearchingClient // ignore: cast_nullable_to_non_nullable
as bool,useCustomAddress: null == useCustomAddress ? _self.useCustomAddress : useCustomAddress // ignore: cast_nullable_to_non_nullable
as bool,isPersonal: null == isPersonal ? _self.isPersonal : isPersonal // ignore: cast_nullable_to_non_nullable
as bool,isDayOff: null == isDayOff ? _self.isDayOff : isDayOff // ignore: cast_nullable_to_non_nullable
as bool,isAllDay: null == isAllDay ? _self.isAllDay : isAllDay // ignore: cast_nullable_to_non_nullable
as bool,clientCleared: null == clientCleared ? _self.clientCleared : clientCleared // ignore: cast_nullable_to_non_nullable
as bool,errors: null == errors ? _self._errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, AppointmentFormError>,
  ));
}

/// Create a copy of EventDetailsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientRecordCopyWith<$Res>? get client {
    if (_self.client == null) {
    return null;
  }

  return $ClientRecordCopyWith<$Res>(_self.client!, (value) {
    return _then(_self.copyWith(client: value));
  });
}/// Create a copy of EventDetailsState
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
}
}

// dart format on
