// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'event_details_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EventDetailsState {

 DateTime get selectedDate; DateTime get endDate; TimeOfDay get selectedStartTime; TimeOfDay get selectedEndTime; String get editingStatus; bool get isEditing;/// An existing record already has a real end date, so unlike the add flow
/// this starts true: moving the start date must preserve the run's LENGTH
/// rather than collapse it to a single day.
 bool get endDateTouched; RepeatInterval get repeat;// The repeat value as last saved — if the user changes it, that triggers new bookings.
 RepeatInterval get savedRepeat; List<EmployeeRecord> get selectedEmployees; List<AppointmentImage> get existingImages; List<AppointmentImage> get removedExistingImages; List<File> get newImages; bool get isSaving; ClientRecord? get client; ClientRecord? get selectedClient; List<ClientRecord> get clientResults; bool get isSearchingClient; bool get useCustomAddress; bool get isPersonal; bool get isAllDay;// Set when the user explicitly removes the client, so we don't fall back to a placeholder.
 bool get clientCleared; Map<String, AppointmentFormError> get errors;
/// Create a copy of EventDetailsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventDetailsStateCopyWith<EventDetailsState> get copyWith => _$EventDetailsStateCopyWithImpl<EventDetailsState>(this as EventDetailsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventDetailsState&&(identical(other.selectedDate, selectedDate) || other.selectedDate == selectedDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.selectedStartTime, selectedStartTime) || other.selectedStartTime == selectedStartTime)&&(identical(other.selectedEndTime, selectedEndTime) || other.selectedEndTime == selectedEndTime)&&(identical(other.editingStatus, editingStatus) || other.editingStatus == editingStatus)&&(identical(other.isEditing, isEditing) || other.isEditing == isEditing)&&(identical(other.endDateTouched, endDateTouched) || other.endDateTouched == endDateTouched)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.savedRepeat, savedRepeat) || other.savedRepeat == savedRepeat)&&const DeepCollectionEquality().equals(other.selectedEmployees, selectedEmployees)&&const DeepCollectionEquality().equals(other.existingImages, existingImages)&&const DeepCollectionEquality().equals(other.removedExistingImages, removedExistingImages)&&const DeepCollectionEquality().equals(other.newImages, newImages)&&(identical(other.isSaving, isSaving) || other.isSaving == isSaving)&&(identical(other.client, client) || other.client == client)&&(identical(other.selectedClient, selectedClient) || other.selectedClient == selectedClient)&&const DeepCollectionEquality().equals(other.clientResults, clientResults)&&(identical(other.isSearchingClient, isSearchingClient) || other.isSearchingClient == isSearchingClient)&&(identical(other.useCustomAddress, useCustomAddress) || other.useCustomAddress == useCustomAddress)&&(identical(other.isPersonal, isPersonal) || other.isPersonal == isPersonal)&&(identical(other.isAllDay, isAllDay) || other.isAllDay == isAllDay)&&(identical(other.clientCleared, clientCleared) || other.clientCleared == clientCleared)&&const DeepCollectionEquality().equals(other.errors, errors));
}


@override
int get hashCode => Object.hashAll([runtimeType,selectedDate,endDate,selectedStartTime,selectedEndTime,editingStatus,isEditing,endDateTouched,repeat,savedRepeat,const DeepCollectionEquality().hash(selectedEmployees),const DeepCollectionEquality().hash(existingImages),const DeepCollectionEquality().hash(removedExistingImages),const DeepCollectionEquality().hash(newImages),isSaving,client,selectedClient,const DeepCollectionEquality().hash(clientResults),isSearchingClient,useCustomAddress,isPersonal,isAllDay,clientCleared,const DeepCollectionEquality().hash(errors)]);

@override
String toString() {
  return 'EventDetailsState(selectedDate: $selectedDate, endDate: $endDate, selectedStartTime: $selectedStartTime, selectedEndTime: $selectedEndTime, editingStatus: $editingStatus, isEditing: $isEditing, endDateTouched: $endDateTouched, repeat: $repeat, savedRepeat: $savedRepeat, selectedEmployees: $selectedEmployees, existingImages: $existingImages, removedExistingImages: $removedExistingImages, newImages: $newImages, isSaving: $isSaving, client: $client, selectedClient: $selectedClient, clientResults: $clientResults, isSearchingClient: $isSearchingClient, useCustomAddress: $useCustomAddress, isPersonal: $isPersonal, isAllDay: $isAllDay, clientCleared: $clientCleared, errors: $errors)';
}


}

/// @nodoc
abstract mixin class $EventDetailsStateCopyWith<$Res>  {
  factory $EventDetailsStateCopyWith(EventDetailsState value, $Res Function(EventDetailsState) _then) = _$EventDetailsStateCopyWithImpl;
@useResult
$Res call({
 DateTime selectedDate, DateTime endDate, TimeOfDay selectedStartTime, TimeOfDay selectedEndTime, String editingStatus, bool isEditing, bool endDateTouched, RepeatInterval repeat, RepeatInterval savedRepeat, List<EmployeeRecord> selectedEmployees, List<AppointmentImage> existingImages, List<AppointmentImage> removedExistingImages, List<File> newImages, bool isSaving, ClientRecord? client, ClientRecord? selectedClient, List<ClientRecord> clientResults, bool isSearchingClient, bool useCustomAddress, bool isPersonal, bool isAllDay, bool clientCleared, Map<String, AppointmentFormError> errors
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
@pragma('vm:prefer-inline') @override $Res call({Object? selectedDate = null,Object? endDate = null,Object? selectedStartTime = null,Object? selectedEndTime = null,Object? editingStatus = null,Object? isEditing = null,Object? endDateTouched = null,Object? repeat = null,Object? savedRepeat = null,Object? selectedEmployees = null,Object? existingImages = null,Object? removedExistingImages = null,Object? newImages = null,Object? isSaving = null,Object? client = freezed,Object? selectedClient = freezed,Object? clientResults = null,Object? isSearchingClient = null,Object? useCustomAddress = null,Object? isPersonal = null,Object? isAllDay = null,Object? clientCleared = null,Object? errors = null,}) {
  return _then(_self.copyWith(
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime selectedDate,  DateTime endDate,  TimeOfDay selectedStartTime,  TimeOfDay selectedEndTime,  String editingStatus,  bool isEditing,  bool endDateTouched,  RepeatInterval repeat,  RepeatInterval savedRepeat,  List<EmployeeRecord> selectedEmployees,  List<AppointmentImage> existingImages,  List<AppointmentImage> removedExistingImages,  List<File> newImages,  bool isSaving,  ClientRecord? client,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  bool useCustomAddress,  bool isPersonal,  bool isAllDay,  bool clientCleared,  Map<String, AppointmentFormError> errors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EventDetailsState() when $default != null:
return $default(_that.selectedDate,_that.endDate,_that.selectedStartTime,_that.selectedEndTime,_that.editingStatus,_that.isEditing,_that.endDateTouched,_that.repeat,_that.savedRepeat,_that.selectedEmployees,_that.existingImages,_that.removedExistingImages,_that.newImages,_that.isSaving,_that.client,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.useCustomAddress,_that.isPersonal,_that.isAllDay,_that.clientCleared,_that.errors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime selectedDate,  DateTime endDate,  TimeOfDay selectedStartTime,  TimeOfDay selectedEndTime,  String editingStatus,  bool isEditing,  bool endDateTouched,  RepeatInterval repeat,  RepeatInterval savedRepeat,  List<EmployeeRecord> selectedEmployees,  List<AppointmentImage> existingImages,  List<AppointmentImage> removedExistingImages,  List<File> newImages,  bool isSaving,  ClientRecord? client,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  bool useCustomAddress,  bool isPersonal,  bool isAllDay,  bool clientCleared,  Map<String, AppointmentFormError> errors)  $default,) {final _that = this;
switch (_that) {
case _EventDetailsState():
return $default(_that.selectedDate,_that.endDate,_that.selectedStartTime,_that.selectedEndTime,_that.editingStatus,_that.isEditing,_that.endDateTouched,_that.repeat,_that.savedRepeat,_that.selectedEmployees,_that.existingImages,_that.removedExistingImages,_that.newImages,_that.isSaving,_that.client,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.useCustomAddress,_that.isPersonal,_that.isAllDay,_that.clientCleared,_that.errors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime selectedDate,  DateTime endDate,  TimeOfDay selectedStartTime,  TimeOfDay selectedEndTime,  String editingStatus,  bool isEditing,  bool endDateTouched,  RepeatInterval repeat,  RepeatInterval savedRepeat,  List<EmployeeRecord> selectedEmployees,  List<AppointmentImage> existingImages,  List<AppointmentImage> removedExistingImages,  List<File> newImages,  bool isSaving,  ClientRecord? client,  ClientRecord? selectedClient,  List<ClientRecord> clientResults,  bool isSearchingClient,  bool useCustomAddress,  bool isPersonal,  bool isAllDay,  bool clientCleared,  Map<String, AppointmentFormError> errors)?  $default,) {final _that = this;
switch (_that) {
case _EventDetailsState() when $default != null:
return $default(_that.selectedDate,_that.endDate,_that.selectedStartTime,_that.selectedEndTime,_that.editingStatus,_that.isEditing,_that.endDateTouched,_that.repeat,_that.savedRepeat,_that.selectedEmployees,_that.existingImages,_that.removedExistingImages,_that.newImages,_that.isSaving,_that.client,_that.selectedClient,_that.clientResults,_that.isSearchingClient,_that.useCustomAddress,_that.isPersonal,_that.isAllDay,_that.clientCleared,_that.errors);case _:
  return null;

}
}

}

/// @nodoc


class _EventDetailsState implements EventDetailsState {
  const _EventDetailsState({required this.selectedDate, required this.endDate, required this.selectedStartTime, required this.selectedEndTime, required this.editingStatus, this.isEditing = false, this.endDateTouched = true, this.repeat = RepeatInterval.none, this.savedRepeat = RepeatInterval.none, final  List<EmployeeRecord> selectedEmployees = const <EmployeeRecord>[], final  List<AppointmentImage> existingImages = const <AppointmentImage>[], final  List<AppointmentImage> removedExistingImages = const <AppointmentImage>[], final  List<File> newImages = const <File>[], this.isSaving = false, this.client, this.selectedClient, final  List<ClientRecord> clientResults = const <ClientRecord>[], this.isSearchingClient = false, this.useCustomAddress = false, this.isPersonal = false, this.isAllDay = false, this.clientCleared = false, final  Map<String, AppointmentFormError> errors = const <String, AppointmentFormError>{}}): _selectedEmployees = selectedEmployees,_existingImages = existingImages,_removedExistingImages = removedExistingImages,_newImages = newImages,_clientResults = clientResults,_errors = errors;
  

@override final  DateTime selectedDate;
@override final  DateTime endDate;
@override final  TimeOfDay selectedStartTime;
@override final  TimeOfDay selectedEndTime;
@override final  String editingStatus;
@override@JsonKey() final  bool isEditing;
/// An existing record already has a real end date, so unlike the add flow
/// this starts true: moving the start date must preserve the run's LENGTH
/// rather than collapse it to a single day.
@override@JsonKey() final  bool endDateTouched;
@override@JsonKey() final  RepeatInterval repeat;
// The repeat value as last saved — if the user changes it, that triggers new bookings.
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
@override@JsonKey() final  bool isAllDay;
// Set when the user explicitly removes the client, so we don't fall back to a placeholder.
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EventDetailsState&&(identical(other.selectedDate, selectedDate) || other.selectedDate == selectedDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.selectedStartTime, selectedStartTime) || other.selectedStartTime == selectedStartTime)&&(identical(other.selectedEndTime, selectedEndTime) || other.selectedEndTime == selectedEndTime)&&(identical(other.editingStatus, editingStatus) || other.editingStatus == editingStatus)&&(identical(other.isEditing, isEditing) || other.isEditing == isEditing)&&(identical(other.endDateTouched, endDateTouched) || other.endDateTouched == endDateTouched)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.savedRepeat, savedRepeat) || other.savedRepeat == savedRepeat)&&const DeepCollectionEquality().equals(other._selectedEmployees, _selectedEmployees)&&const DeepCollectionEquality().equals(other._existingImages, _existingImages)&&const DeepCollectionEquality().equals(other._removedExistingImages, _removedExistingImages)&&const DeepCollectionEquality().equals(other._newImages, _newImages)&&(identical(other.isSaving, isSaving) || other.isSaving == isSaving)&&(identical(other.client, client) || other.client == client)&&(identical(other.selectedClient, selectedClient) || other.selectedClient == selectedClient)&&const DeepCollectionEquality().equals(other._clientResults, _clientResults)&&(identical(other.isSearchingClient, isSearchingClient) || other.isSearchingClient == isSearchingClient)&&(identical(other.useCustomAddress, useCustomAddress) || other.useCustomAddress == useCustomAddress)&&(identical(other.isPersonal, isPersonal) || other.isPersonal == isPersonal)&&(identical(other.isAllDay, isAllDay) || other.isAllDay == isAllDay)&&(identical(other.clientCleared, clientCleared) || other.clientCleared == clientCleared)&&const DeepCollectionEquality().equals(other._errors, _errors));
}


@override
int get hashCode => Object.hashAll([runtimeType,selectedDate,endDate,selectedStartTime,selectedEndTime,editingStatus,isEditing,endDateTouched,repeat,savedRepeat,const DeepCollectionEquality().hash(_selectedEmployees),const DeepCollectionEquality().hash(_existingImages),const DeepCollectionEquality().hash(_removedExistingImages),const DeepCollectionEquality().hash(_newImages),isSaving,client,selectedClient,const DeepCollectionEquality().hash(_clientResults),isSearchingClient,useCustomAddress,isPersonal,isAllDay,clientCleared,const DeepCollectionEquality().hash(_errors)]);

@override
String toString() {
  return 'EventDetailsState(selectedDate: $selectedDate, endDate: $endDate, selectedStartTime: $selectedStartTime, selectedEndTime: $selectedEndTime, editingStatus: $editingStatus, isEditing: $isEditing, endDateTouched: $endDateTouched, repeat: $repeat, savedRepeat: $savedRepeat, selectedEmployees: $selectedEmployees, existingImages: $existingImages, removedExistingImages: $removedExistingImages, newImages: $newImages, isSaving: $isSaving, client: $client, selectedClient: $selectedClient, clientResults: $clientResults, isSearchingClient: $isSearchingClient, useCustomAddress: $useCustomAddress, isPersonal: $isPersonal, isAllDay: $isAllDay, clientCleared: $clientCleared, errors: $errors)';
}


}

/// @nodoc
abstract mixin class _$EventDetailsStateCopyWith<$Res> implements $EventDetailsStateCopyWith<$Res> {
  factory _$EventDetailsStateCopyWith(_EventDetailsState value, $Res Function(_EventDetailsState) _then) = __$EventDetailsStateCopyWithImpl;
@override @useResult
$Res call({
 DateTime selectedDate, DateTime endDate, TimeOfDay selectedStartTime, TimeOfDay selectedEndTime, String editingStatus, bool isEditing, bool endDateTouched, RepeatInterval repeat, RepeatInterval savedRepeat, List<EmployeeRecord> selectedEmployees, List<AppointmentImage> existingImages, List<AppointmentImage> removedExistingImages, List<File> newImages, bool isSaving, ClientRecord? client, ClientRecord? selectedClient, List<ClientRecord> clientResults, bool isSearchingClient, bool useCustomAddress, bool isPersonal, bool isAllDay, bool clientCleared, Map<String, AppointmentFormError> errors
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
@override @pragma('vm:prefer-inline') $Res call({Object? selectedDate = null,Object? endDate = null,Object? selectedStartTime = null,Object? selectedEndTime = null,Object? editingStatus = null,Object? isEditing = null,Object? endDateTouched = null,Object? repeat = null,Object? savedRepeat = null,Object? selectedEmployees = null,Object? existingImages = null,Object? removedExistingImages = null,Object? newImages = null,Object? isSaving = null,Object? client = freezed,Object? selectedClient = freezed,Object? clientResults = null,Object? isSearchingClient = null,Object? useCustomAddress = null,Object? isPersonal = null,Object? isAllDay = null,Object? clientCleared = null,Object? errors = null,}) {
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
