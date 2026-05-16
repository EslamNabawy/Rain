// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PeerConnectionView {

 String get peerId; Session? get session; String? get localDetail; Object? get error; ManualConnectionIntent get manualIntent; bool get actionBusy; bool get disconnecting; int? get updatedAt;
/// Create a copy of PeerConnectionView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PeerConnectionViewCopyWith<PeerConnectionView> get copyWith => _$PeerConnectionViewCopyWithImpl<PeerConnectionView>(this as PeerConnectionView, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PeerConnectionView&&(identical(other.peerId, peerId) || other.peerId == peerId)&&(identical(other.session, session) || other.session == session)&&(identical(other.localDetail, localDetail) || other.localDetail == localDetail)&&const DeepCollectionEquality().equals(other.error, error)&&(identical(other.manualIntent, manualIntent) || other.manualIntent == manualIntent)&&(identical(other.actionBusy, actionBusy) || other.actionBusy == actionBusy)&&(identical(other.disconnecting, disconnecting) || other.disconnecting == disconnecting)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,peerId,session,localDetail,const DeepCollectionEquality().hash(error),manualIntent,actionBusy,disconnecting,updatedAt);

@override
String toString() {
  return 'PeerConnectionView(peerId: $peerId, session: $session, localDetail: $localDetail, error: $error, manualIntent: $manualIntent, actionBusy: $actionBusy, disconnecting: $disconnecting, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $PeerConnectionViewCopyWith<$Res>  {
  factory $PeerConnectionViewCopyWith(PeerConnectionView value, $Res Function(PeerConnectionView) _then) = _$PeerConnectionViewCopyWithImpl;
@useResult
$Res call({
 String peerId, Session? session, String? localDetail, Object? error, ManualConnectionIntent manualIntent, bool actionBusy, bool disconnecting, int? updatedAt
});




}
/// @nodoc
class _$PeerConnectionViewCopyWithImpl<$Res>
    implements $PeerConnectionViewCopyWith<$Res> {
  _$PeerConnectionViewCopyWithImpl(this._self, this._then);

  final PeerConnectionView _self;
  final $Res Function(PeerConnectionView) _then;

/// Create a copy of PeerConnectionView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? peerId = null,Object? session = freezed,Object? localDetail = freezed,Object? error = freezed,Object? manualIntent = null,Object? actionBusy = null,Object? disconnecting = null,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
peerId: null == peerId ? _self.peerId : peerId // ignore: cast_nullable_to_non_nullable
as String,session: freezed == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as Session?,localDetail: freezed == localDetail ? _self.localDetail : localDetail // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error ,manualIntent: null == manualIntent ? _self.manualIntent : manualIntent // ignore: cast_nullable_to_non_nullable
as ManualConnectionIntent,actionBusy: null == actionBusy ? _self.actionBusy : actionBusy // ignore: cast_nullable_to_non_nullable
as bool,disconnecting: null == disconnecting ? _self.disconnecting : disconnecting // ignore: cast_nullable_to_non_nullable
as bool,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PeerConnectionView].
extension PeerConnectionViewPatterns on PeerConnectionView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PeerConnectionView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PeerConnectionView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PeerConnectionView value)  $default,){
final _that = this;
switch (_that) {
case _PeerConnectionView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PeerConnectionView value)?  $default,){
final _that = this;
switch (_that) {
case _PeerConnectionView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String peerId,  Session? session,  String? localDetail,  Object? error,  ManualConnectionIntent manualIntent,  bool actionBusy,  bool disconnecting,  int? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PeerConnectionView() when $default != null:
return $default(_that.peerId,_that.session,_that.localDetail,_that.error,_that.manualIntent,_that.actionBusy,_that.disconnecting,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String peerId,  Session? session,  String? localDetail,  Object? error,  ManualConnectionIntent manualIntent,  bool actionBusy,  bool disconnecting,  int? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _PeerConnectionView():
return $default(_that.peerId,_that.session,_that.localDetail,_that.error,_that.manualIntent,_that.actionBusy,_that.disconnecting,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String peerId,  Session? session,  String? localDetail,  Object? error,  ManualConnectionIntent manualIntent,  bool actionBusy,  bool disconnecting,  int? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _PeerConnectionView() when $default != null:
return $default(_that.peerId,_that.session,_that.localDetail,_that.error,_that.manualIntent,_that.actionBusy,_that.disconnecting,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _PeerConnectionView extends PeerConnectionView {
  const _PeerConnectionView({required this.peerId, this.session, this.localDetail, this.error, this.manualIntent = ManualConnectionIntent.idle, this.actionBusy = false, this.disconnecting = false, this.updatedAt}): super._();
  

@override final  String peerId;
@override final  Session? session;
@override final  String? localDetail;
@override final  Object? error;
@override@JsonKey() final  ManualConnectionIntent manualIntent;
@override@JsonKey() final  bool actionBusy;
@override@JsonKey() final  bool disconnecting;
@override final  int? updatedAt;

/// Create a copy of PeerConnectionView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PeerConnectionViewCopyWith<_PeerConnectionView> get copyWith => __$PeerConnectionViewCopyWithImpl<_PeerConnectionView>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PeerConnectionView&&(identical(other.peerId, peerId) || other.peerId == peerId)&&(identical(other.session, session) || other.session == session)&&(identical(other.localDetail, localDetail) || other.localDetail == localDetail)&&const DeepCollectionEquality().equals(other.error, error)&&(identical(other.manualIntent, manualIntent) || other.manualIntent == manualIntent)&&(identical(other.actionBusy, actionBusy) || other.actionBusy == actionBusy)&&(identical(other.disconnecting, disconnecting) || other.disconnecting == disconnecting)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,peerId,session,localDetail,const DeepCollectionEquality().hash(error),manualIntent,actionBusy,disconnecting,updatedAt);

@override
String toString() {
  return 'PeerConnectionView(peerId: $peerId, session: $session, localDetail: $localDetail, error: $error, manualIntent: $manualIntent, actionBusy: $actionBusy, disconnecting: $disconnecting, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$PeerConnectionViewCopyWith<$Res> implements $PeerConnectionViewCopyWith<$Res> {
  factory _$PeerConnectionViewCopyWith(_PeerConnectionView value, $Res Function(_PeerConnectionView) _then) = __$PeerConnectionViewCopyWithImpl;
@override @useResult
$Res call({
 String peerId, Session? session, String? localDetail, Object? error, ManualConnectionIntent manualIntent, bool actionBusy, bool disconnecting, int? updatedAt
});




}
/// @nodoc
class __$PeerConnectionViewCopyWithImpl<$Res>
    implements _$PeerConnectionViewCopyWith<$Res> {
  __$PeerConnectionViewCopyWithImpl(this._self, this._then);

  final _PeerConnectionView _self;
  final $Res Function(_PeerConnectionView) _then;

/// Create a copy of PeerConnectionView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? peerId = null,Object? session = freezed,Object? localDetail = freezed,Object? error = freezed,Object? manualIntent = null,Object? actionBusy = null,Object? disconnecting = null,Object? updatedAt = freezed,}) {
  return _then(_PeerConnectionView(
peerId: null == peerId ? _self.peerId : peerId // ignore: cast_nullable_to_non_nullable
as String,session: freezed == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as Session?,localDetail: freezed == localDetail ? _self.localDetail : localDetail // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error ,manualIntent: null == manualIntent ? _self.manualIntent : manualIntent // ignore: cast_nullable_to_non_nullable
as ManualConnectionIntent,actionBusy: null == actionBusy ? _self.actionBusy : actionBusy // ignore: cast_nullable_to_non_nullable
as bool,disconnecting: null == disconnecting ? _self.disconnecting : disconnecting // ignore: cast_nullable_to_non_nullable
as bool,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$ConnectionsState {

 Map<String, PeerConnectionView> get peers;
/// Create a copy of ConnectionsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionsStateCopyWith<ConnectionsState> get copyWith => _$ConnectionsStateCopyWithImpl<ConnectionsState>(this as ConnectionsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionsState&&const DeepCollectionEquality().equals(other.peers, peers));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(peers));

@override
String toString() {
  return 'ConnectionsState(peers: $peers)';
}


}

/// @nodoc
abstract mixin class $ConnectionsStateCopyWith<$Res>  {
  factory $ConnectionsStateCopyWith(ConnectionsState value, $Res Function(ConnectionsState) _then) = _$ConnectionsStateCopyWithImpl;
@useResult
$Res call({
 Map<String, PeerConnectionView> peers
});




}
/// @nodoc
class _$ConnectionsStateCopyWithImpl<$Res>
    implements $ConnectionsStateCopyWith<$Res> {
  _$ConnectionsStateCopyWithImpl(this._self, this._then);

  final ConnectionsState _self;
  final $Res Function(ConnectionsState) _then;

/// Create a copy of ConnectionsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? peers = null,}) {
  return _then(_self.copyWith(
peers: null == peers ? _self.peers : peers // ignore: cast_nullable_to_non_nullable
as Map<String, PeerConnectionView>,
  ));
}

}


/// Adds pattern-matching-related methods to [ConnectionsState].
extension ConnectionsStatePatterns on ConnectionsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectionsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectionsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectionsState value)  $default,){
final _that = this;
switch (_that) {
case _ConnectionsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectionsState value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectionsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, PeerConnectionView> peers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectionsState() when $default != null:
return $default(_that.peers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, PeerConnectionView> peers)  $default,) {final _that = this;
switch (_that) {
case _ConnectionsState():
return $default(_that.peers);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, PeerConnectionView> peers)?  $default,) {final _that = this;
switch (_that) {
case _ConnectionsState() when $default != null:
return $default(_that.peers);case _:
  return null;

}
}

}

/// @nodoc


class _ConnectionsState extends ConnectionsState {
  const _ConnectionsState({final  Map<String, PeerConnectionView> peers = const <String, PeerConnectionView>{}}): _peers = peers,super._();
  

 final  Map<String, PeerConnectionView> _peers;
@override@JsonKey() Map<String, PeerConnectionView> get peers {
  if (_peers is EqualUnmodifiableMapView) return _peers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_peers);
}


/// Create a copy of ConnectionsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionsStateCopyWith<_ConnectionsState> get copyWith => __$ConnectionsStateCopyWithImpl<_ConnectionsState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectionsState&&const DeepCollectionEquality().equals(other._peers, _peers));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_peers));

@override
String toString() {
  return 'ConnectionsState(peers: $peers)';
}


}

/// @nodoc
abstract mixin class _$ConnectionsStateCopyWith<$Res> implements $ConnectionsStateCopyWith<$Res> {
  factory _$ConnectionsStateCopyWith(_ConnectionsState value, $Res Function(_ConnectionsState) _then) = __$ConnectionsStateCopyWithImpl;
@override @useResult
$Res call({
 Map<String, PeerConnectionView> peers
});




}
/// @nodoc
class __$ConnectionsStateCopyWithImpl<$Res>
    implements _$ConnectionsStateCopyWith<$Res> {
  __$ConnectionsStateCopyWithImpl(this._self, this._then);

  final _ConnectionsState _self;
  final $Res Function(_ConnectionsState) _then;

/// Create a copy of ConnectionsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? peers = null,}) {
  return _then(_ConnectionsState(
peers: null == peers ? _self._peers : peers // ignore: cast_nullable_to_non_nullable
as Map<String, PeerConnectionView>,
  ));
}


}

/// @nodoc
mixin _$UserSearchState {

 String get query; List<BackendIdentity> get results; String? get sendingTo;
/// Create a copy of UserSearchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserSearchStateCopyWith<UserSearchState> get copyWith => _$UserSearchStateCopyWithImpl<UserSearchState>(this as UserSearchState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserSearchState&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other.results, results)&&(identical(other.sendingTo, sendingTo) || other.sendingTo == sendingTo));
}


@override
int get hashCode => Object.hash(runtimeType,query,const DeepCollectionEquality().hash(results),sendingTo);

@override
String toString() {
  return 'UserSearchState(query: $query, results: $results, sendingTo: $sendingTo)';
}


}

/// @nodoc
abstract mixin class $UserSearchStateCopyWith<$Res>  {
  factory $UserSearchStateCopyWith(UserSearchState value, $Res Function(UserSearchState) _then) = _$UserSearchStateCopyWithImpl;
@useResult
$Res call({
 String query, List<BackendIdentity> results, String? sendingTo
});




}
/// @nodoc
class _$UserSearchStateCopyWithImpl<$Res>
    implements $UserSearchStateCopyWith<$Res> {
  _$UserSearchStateCopyWithImpl(this._self, this._then);

  final UserSearchState _self;
  final $Res Function(UserSearchState) _then;

/// Create a copy of UserSearchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? query = null,Object? results = null,Object? sendingTo = freezed,}) {
  return _then(_self.copyWith(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,results: null == results ? _self.results : results // ignore: cast_nullable_to_non_nullable
as List<BackendIdentity>,sendingTo: freezed == sendingTo ? _self.sendingTo : sendingTo // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [UserSearchState].
extension UserSearchStatePatterns on UserSearchState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UserSearchState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UserSearchState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UserSearchState value)  $default,){
final _that = this;
switch (_that) {
case _UserSearchState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UserSearchState value)?  $default,){
final _that = this;
switch (_that) {
case _UserSearchState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String query,  List<BackendIdentity> results,  String? sendingTo)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UserSearchState() when $default != null:
return $default(_that.query,_that.results,_that.sendingTo);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String query,  List<BackendIdentity> results,  String? sendingTo)  $default,) {final _that = this;
switch (_that) {
case _UserSearchState():
return $default(_that.query,_that.results,_that.sendingTo);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String query,  List<BackendIdentity> results,  String? sendingTo)?  $default,) {final _that = this;
switch (_that) {
case _UserSearchState() when $default != null:
return $default(_that.query,_that.results,_that.sendingTo);case _:
  return null;

}
}

}

/// @nodoc


class _UserSearchState implements UserSearchState {
  const _UserSearchState({this.query = '', final  List<BackendIdentity> results = const <BackendIdentity>[], this.sendingTo}): _results = results;
  

@override@JsonKey() final  String query;
 final  List<BackendIdentity> _results;
@override@JsonKey() List<BackendIdentity> get results {
  if (_results is EqualUnmodifiableListView) return _results;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_results);
}

@override final  String? sendingTo;

/// Create a copy of UserSearchState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserSearchStateCopyWith<_UserSearchState> get copyWith => __$UserSearchStateCopyWithImpl<_UserSearchState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserSearchState&&(identical(other.query, query) || other.query == query)&&const DeepCollectionEquality().equals(other._results, _results)&&(identical(other.sendingTo, sendingTo) || other.sendingTo == sendingTo));
}


@override
int get hashCode => Object.hash(runtimeType,query,const DeepCollectionEquality().hash(_results),sendingTo);

@override
String toString() {
  return 'UserSearchState(query: $query, results: $results, sendingTo: $sendingTo)';
}


}

/// @nodoc
abstract mixin class _$UserSearchStateCopyWith<$Res> implements $UserSearchStateCopyWith<$Res> {
  factory _$UserSearchStateCopyWith(_UserSearchState value, $Res Function(_UserSearchState) _then) = __$UserSearchStateCopyWithImpl;
@override @useResult
$Res call({
 String query, List<BackendIdentity> results, String? sendingTo
});




}
/// @nodoc
class __$UserSearchStateCopyWithImpl<$Res>
    implements _$UserSearchStateCopyWith<$Res> {
  __$UserSearchStateCopyWithImpl(this._self, this._then);

  final _UserSearchState _self;
  final $Res Function(_UserSearchState) _then;

/// Create a copy of UserSearchState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? query = null,Object? results = null,Object? sendingTo = freezed,}) {
  return _then(_UserSearchState(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,results: null == results ? _self._results : results // ignore: cast_nullable_to_non_nullable
as List<BackendIdentity>,sendingTo: freezed == sendingTo ? _self.sendingTo : sendingTo // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
