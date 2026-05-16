import 'package:supabase_flutter/supabase_flutter.dart';

import 'signaling_adapter.dart';

Exception normalizeSupabaseIdentityWriteError(
  Object error, {
  required String username,
}) {
  if (_isUidConflict(error)) {
    return SignalingSessionExpiredException(
      'Supabase is signed in to a different Rain identity than @$username. Sign in again.',
    );
  }

  return error is Exception ? error : Exception(error.toString());
}

bool _isUidConflict(Object error) {
  if (error is! PostgrestException || error.code != '23505') {
    return false;
  }
  final combined = '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
      .toLowerCase();
  return combined.contains('users_uid_key');
}
