import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/src/registration_flow.dart';

RegistrationSteps _steps(
  List<String> log, {
  String? failAt,
  bool permissionDenied = false,
}) {
  Future<void> step(String name) async {
    log.add(name);
    if (failAt == name) {
      throw Exception(permissionDenied ? 'permission denied' : 'boom');
    }
  }

  return RegistrationSteps(
    writeUserRow: () => step('row'),
    writeSearchEntry: () => step('search'),
    setOnline: () => step('presence'),
    signIn: () => step('signIn'),
    deleteNewAuthUser: () => step('deleteAuth'),
    signOutLocal: () => step('signOut'),
    isPermissionDenied: (Object e) => e.toString().contains('permission'),
    takenMessage: 'taken or locked',
  );
}

void main() {
  test('success runs every step and no rollback', () async {
    final log = <String>[];
    await runRegistrationBackendSteps(_steps(log));
    expect(log, <String>['row', 'search', 'presence', 'signIn']);
  });

  test(
    'failed user row deletes the new auth user before signing out',
    () async {
      final log = <String>[];
      await expectLater(
        runRegistrationBackendSteps(_steps(log, failAt: 'row')),
        throwsException,
      );
      expect(log, <String>['row', 'deleteAuth', 'signOut']);
    },
  );

  test(
    'failure after the user row keeps the auth user and signs out',
    () async {
      final log = <String>[];
      await expectLater(
        runRegistrationBackendSteps(_steps(log, failAt: 'search')),
        throwsException,
      );
      expect(log, <String>['row', 'search', 'signOut']);
    },
  );

  test('permission denied maps to the taken or locked message', () async {
    final log = <String>[];
    await expectLater(
      runRegistrationBackendSteps(
        _steps(log, failAt: 'row', permissionDenied: true),
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('taken or locked'),
        ),
      ),
    );
    expect(log, <String>['row', 'deleteAuth', 'signOut']);
  });
}
