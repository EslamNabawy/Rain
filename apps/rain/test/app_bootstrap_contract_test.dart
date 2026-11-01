import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Firebase bootstrap configures the pair resolver after adapter creation',
    () {
      final source = File(
        'lib/application/bootstrap/app_bootstrap.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('final createdAdapter = FirebaseSignalingAdapter('),
      );
      expect(source, contains('createdAdapter.configurePairCipherResolver('));
      expect(source, contains('adapter: createdAdapter'));
      expect(source, isNot(contains('adapter: firebaseAdapter!')));
    },
  );
}
