import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_brand_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Rain brand runtime assets are bundled', () async {
    for (final path in RainBrandAssets.runtimeAssets) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });
}
