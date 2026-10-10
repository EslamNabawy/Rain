/// Steps of the registration sequence, injected so the rollback ordering can
/// be unit tested without Firebase.
final class RegistrationSteps {
  const RegistrationSteps({
    required this.writeUserRow,
    required this.writeSearchEntry,
    required this.setOnline,
    required this.signIn,
    required this.deleteNewAuthUser,
    required this.signOutLocal,
    required this.isPermissionDenied,
    required this.takenMessage,
  });

  /// Writes the durable `users/<name>` row.
  final Future<void> Function() writeUserRow;
  final Future<void> Function() writeSearchEntry;
  final Future<void> Function() setOnline;
  final Future<void> Function() signIn;

  /// Deletes the Auth user that was just created. Must run while that user is
  /// still the signed-in user, so it has to run before [signOutLocal].
  final Future<void> Function() deleteNewAuthUser;
  final Future<void> Function() signOutLocal;
  final bool Function(Object error) isPermissionDenied;
  final String takenMessage;
}

/// Runs the backend part of registration after the Auth user exists.
///
/// If the durable user row was never written, the new Auth user is deleted
/// (then the local session is signed out) so the username is not left taken.
/// If the row exists, only the local session is cleared.
Future<void> runRegistrationBackendSteps(RegistrationSteps steps) async {
  var backendUserCreated = false;
  try {
    await steps.writeUserRow();
    backendUserCreated = true;
    await steps.writeSearchEntry();
    await steps.setOnline();
    await steps.signIn();
  } catch (error) {
    if (!backendUserCreated) {
      await _bestEffort(steps.deleteNewAuthUser);
    }
    await _bestEffort(steps.signOutLocal);
    if (steps.isPermissionDenied(error)) {
      throw Exception(steps.takenMessage);
    }
    rethrow;
  }
}

Future<void> _bestEffort(Future<void> Function() step) async {
  try {
    await step();
  } catch (_) {
    // Cleanup after a failed registration must not mask the original error.
  }
}
