import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

void main() {
  const files = <String>[
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
    'SpaceGrotesk-Medium.ttf',
    'SpaceGrotesk-SemiBold.ttf',
    'SpaceGrotesk-Bold.ttf',
    'Inter-OFL.txt',
    'SpaceGrotesk-OFL.txt',
  ];

  for (final name in files) {
    test('bundled font asset $name exists', () {
      final file = File('assets/google_fonts/$name');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000));
    });
  }

  testWidgets('theme fonts resolve from bundled assets without fetching', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    RainTheme.dark();
    await GoogleFonts.pendingFonts();
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
  });
}
