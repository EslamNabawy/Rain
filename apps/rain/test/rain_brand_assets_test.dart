/// # rain_brand_assets_test.dart
///
/// Verifies that all Rain brand runtime assets are properly bundled and non-empty. Checks every asset path in RainBrandAssets.runtimeAssets.
///
/// **Key types:** RainBrandAssets
///
/// **Depends on:** flutter_test, rain rain_brand_assets

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
