# Rain App Rebrand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the locked Rain `Signal Mist` brand identity to the maintained Flutter app using the created Peer Core assets.

**Architecture:** Keep editable brand sources under `apps/rain/assets/branding/source/`, generated/previews under `apps/rain/assets/branding/generated/`, and runtime-only assets behind a Dart asset registry. Add small presentation-layer branding widgets and reuse them across splash, header, state surfaces, navigation treatment, chat, file transfer, and calls.

**Tech Stack:** Flutter, Dart, Material 3, Riverpod, `flutter_svg`, existing `google_fonts`, Melos.

---

## File Structure

Create:

- `apps/rain/lib/presentation/branding/rain_brand_assets.dart` - typed asset path registry.
- `apps/rain/lib/presentation/branding/rain_peer_core_mark.dart` - static and animated Peer Core mark widgets.
- `apps/rain/lib/presentation/branding/rain_streak_surface.dart` - Rain Streak active-state overlay.
- `apps/rain/lib/presentation/branding/rain_state_surfaces.dart` - Mist State Card and Rain Streak skeletons.
- `apps/rain/assets/branding/runtime/peer_core/` - runtime SVG layers copied from approved animation layers.
- `apps/rain/test/rain_brand_assets_test.dart` - asset bundle coverage.
- `apps/rain/test/rain_brand_mark_test.dart` - logo widget coverage.
- `apps/rain/test/rain_state_surfaces_test.dart` - empty/loading/error surface coverage.

Modify:

- `apps/rain/pubspec.yaml`
- `apps/rain/lib/presentation/theme/rain_theme.dart`
- `apps/rain/lib/presentation/widgets/rain_backdrop.dart`
- `apps/rain/lib/presentation/screens/splash_screen.dart`
- `apps/rain/lib/presentation/widgets/home/shell_header.dart`
- `apps/rain/lib/presentation/widgets/app_components.dart`
- `apps/rain/lib/presentation/navigation/rain_navigation_shell.dart`
- `apps/rain/lib/presentation/widgets/home/friends_list.dart`
- `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- `apps/rain/lib/presentation/screens/search_screen.dart`
- `apps/rain/lib/presentation/screens/root_screen.dart`
- `apps/rain/lib/presentation/screens/settings_screen.dart`
- `apps/rain/lib/presentation/widgets/home/link_status.dart`
- `apps/rain/lib/presentation/widgets/home/file_transfer_bubble.dart`
- `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Existing focused widget tests for the touched screens.

---

### Task 1: Asset Boundary And Registry

**Files:**
- Create: `apps/rain/assets/branding/runtime/peer_core/*.svg`
- Create: `apps/rain/lib/presentation/branding/rain_brand_assets.dart`
- Create: `apps/rain/test/rain_brand_assets_test.dart`
- Modify: `apps/rain/pubspec.yaml`

- [x] **Step 1: Create runtime asset copies**

Run:

```powershell
New-Item -ItemType Directory -Force -Path apps/rain/assets/branding/runtime/peer_core
Copy-Item apps/rain/assets/branding/source/animation/layers/*.svg apps/rain/assets/branding/runtime/peer_core/
```

Expected: runtime folder contains `app_icon_shell.svg`, `rain_streaks.svg`, `wave_inner.svg`, `wave_middle.svg`, `wave_outer.svg`, `ring.svg`, connector SVGs, and `node_a.svg` through `node_c.svg`.

- [x] **Step 2: Narrow `pubspec.yaml` branding assets**

Replace the current broad branding asset entry:

```yaml
    - assets/branding/
```

with:

```yaml
    - assets/branding/rain_app_icon_1024.png
    - assets/branding/rain_logo_premium_1024.png
    - assets/branding/generated/peer_core_app_icon_1024.png
    - assets/branding/generated/peer_core_mark_1024.png
    - assets/branding/generated/peer_core_mark_192.png
    - assets/branding/generated/peer_core_mark_48.png
    - assets/branding/generated/peer_core_mark_tiny_48.png
    - assets/branding/runtime/peer_core/app_icon_shell.svg
    - assets/branding/runtime/peer_core/rain_streaks.svg
    - assets/branding/runtime/peer_core/wave_inner.svg
    - assets/branding/runtime/peer_core/wave_middle.svg
    - assets/branding/runtime/peer_core/wave_outer.svg
    - assets/branding/runtime/peer_core/ring.svg
    - assets/branding/runtime/peer_core/link_node_a_node_b.svg
    - assets/branding/runtime/peer_core/link_node_b_node_c.svg
    - assets/branding/runtime/peer_core/link_node_c_node_a.svg
    - assets/branding/runtime/peer_core/node_a.svg
    - assets/branding/runtime/peer_core/node_b.svg
    - assets/branding/runtime/peer_core/node_c.svg
```

Keep existing gender avatar and sound entries unchanged.

- [x] **Step 3: Add asset registry**

Create `apps/rain/lib/presentation/branding/rain_brand_assets.dart`:

```dart
class RainBrandAssets {
  const RainBrandAssets._();

  static const String legacyAppIcon =
      'assets/branding/rain_app_icon_1024.png';
  static const String legacyLogo =
      'assets/branding/rain_logo_premium_1024.png';

  static const String peerCoreAppIcon =
      'assets/branding/generated/peer_core_app_icon_1024.png';
  static const String peerCoreMark =
      'assets/branding/generated/peer_core_mark_1024.png';
  static const String peerCoreMarkMedium =
      'assets/branding/generated/peer_core_mark_192.png';
  static const String peerCoreMarkSmall =
      'assets/branding/generated/peer_core_mark_48.png';
  static const String peerCoreMarkTiny =
      'assets/branding/generated/peer_core_mark_tiny_48.png';

  static const String layerShell =
      'assets/branding/runtime/peer_core/app_icon_shell.svg';
  static const String layerRainStreaks =
      'assets/branding/runtime/peer_core/rain_streaks.svg';
  static const String layerWaveInner =
      'assets/branding/runtime/peer_core/wave_inner.svg';
  static const String layerWaveMiddle =
      'assets/branding/runtime/peer_core/wave_middle.svg';
  static const String layerWaveOuter =
      'assets/branding/runtime/peer_core/wave_outer.svg';
  static const String layerRing =
      'assets/branding/runtime/peer_core/ring.svg';
  static const String layerLinkAB =
      'assets/branding/runtime/peer_core/link_node_a_node_b.svg';
  static const String layerLinkBC =
      'assets/branding/runtime/peer_core/link_node_b_node_c.svg';
  static const String layerLinkCA =
      'assets/branding/runtime/peer_core/link_node_c_node_a.svg';
  static const String layerNodeA =
      'assets/branding/runtime/peer_core/node_a.svg';
  static const String layerNodeB =
      'assets/branding/runtime/peer_core/node_b.svg';
  static const String layerNodeC =
      'assets/branding/runtime/peer_core/node_c.svg';

  static const List<String> runtimeAssets = <String>[
    peerCoreAppIcon,
    peerCoreMark,
    peerCoreMarkMedium,
    peerCoreMarkSmall,
    peerCoreMarkTiny,
    layerShell,
    layerRainStreaks,
    layerWaveInner,
    layerWaveMiddle,
    layerWaveOuter,
    layerRing,
    layerLinkAB,
    layerLinkBC,
    layerLinkCA,
    layerNodeA,
    layerNodeB,
    layerNodeC,
  ];
}
```

- [x] **Step 4: Add asset bundle test**

Create `apps/rain/test/rain_brand_assets_test.dart`:

```dart
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
```

- [x] **Step 5: Validate Task 1**

Run:

```powershell
cd apps/rain
flutter test test/rain_brand_assets_test.dart
```

Expected: test passes and all runtime asset paths load.

- [x] **Step 6: Commit Task 1**

```powershell
git add apps/rain/pubspec.yaml apps/rain/assets/branding/runtime apps/rain/lib/presentation/branding/rain_brand_assets.dart apps/rain/test/rain_brand_assets_test.dart
git commit -m "feat: register Rain brand runtime assets"
```

---

### Task 2: Peer Core Mark Widgets

**Files:**
- Create: `apps/rain/lib/presentation/branding/rain_peer_core_mark.dart`
- Create: `apps/rain/test/rain_brand_mark_test.dart`

- [x] **Step 1: Add static and animated mark widgets**

Create `apps/rain/lib/presentation/branding/rain_peer_core_mark.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'rain_brand_assets.dart';

class RainPeerCoreMark extends StatelessWidget {
  const RainPeerCoreMark({
    super.key,
    required this.size,
    this.useTinyVariant = false,
    this.semanticLabel = 'Rain',
  });

  final double size;
  final bool useTinyVariant;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final path = useTinyVariant || size < 40
        ? RainBrandAssets.peerCoreMarkTiny
        : size < 96
        ? RainBrandAssets.peerCoreMarkSmall
        : RainBrandAssets.peerCoreMark;

    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
    );
  }
}

class RainPeerCoreAnimatedMark extends StatefulWidget {
  const RainPeerCoreAnimatedMark({
    super.key,
    required this.size,
    this.animate = true,
    this.reducedMotion = false,
  });

  final double size;
  final bool animate;
  final bool reducedMotion;

  @override
  State<RainPeerCoreAnimatedMark> createState() =>
      _RainPeerCoreAnimatedMarkState();
}

class _RainPeerCoreAnimatedMarkState extends State<RainPeerCoreAnimatedMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.animate && !widget.reducedMotion) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(RainPeerCoreAnimatedMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate &&
        !widget.reducedMotion &&
        (!oldWidget.animate || oldWidget.reducedMotion)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reducedMotion) {
      return RainPeerCoreMark(size: widget.size);
    }

    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: <Widget>[
              _WaveLayer(
                asset: RainBrandAssets.layerWaveOuter,
                progress: _delayedProgress(0.18),
              ),
              _WaveLayer(
                asset: RainBrandAssets.layerWaveMiddle,
                progress: _delayedProgress(0.10),
              ),
              _WaveLayer(
                asset: RainBrandAssets.layerWaveInner,
                progress: _delayedProgress(0),
              ),
              SvgPicture.asset(RainBrandAssets.layerRing),
              SvgPicture.asset(RainBrandAssets.layerLinkAB),
              SvgPicture.asset(RainBrandAssets.layerLinkBC),
              SvgPicture.asset(RainBrandAssets.layerLinkCA),
              SvgPicture.asset(RainBrandAssets.layerNodeA),
              SvgPicture.asset(RainBrandAssets.layerNodeB),
              SvgPicture.asset(RainBrandAssets.layerNodeC),
            ],
          );
        },
      ),
    );
  }

  double _delayedProgress(double delay) {
    final value = (_controller.value - delay) / (1 - delay);
    return value.clamp(0, 1);
  }
}

class _WaveLayer extends StatelessWidget {
  const _WaveLayer({required this.asset, required this.progress});

  final String asset;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - progress).clamp(0.0, 1.0);
    final scale = 0.88 + (progress * 0.18);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: SvgPicture.asset(asset),
      ),
    );
  }
}
```

- [x] **Step 2: Add widget tests**

Create `apps/rain/test/rain_brand_mark_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';

void main() {
  testWidgets('RainPeerCoreMark renders static asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RainPeerCoreMark(size: 64)),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('RainPeerCoreAnimatedMark respects reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RainPeerCoreAnimatedMark(size: 96, reducedMotion: true),
      ),
    );

    expect(find.byType(RainPeerCoreMark), findsOneWidget);
  });
}
```

- [x] **Step 3: Validate Task 2**

```powershell
cd apps/rain
flutter test test/rain_brand_mark_test.dart
```

Expected: both tests pass.

- [x] **Step 4: Commit Task 2**

```powershell
git add apps/rain/lib/presentation/branding/rain_peer_core_mark.dart apps/rain/test/rain_brand_mark_test.dart
git commit -m "feat: add Rain Peer Core mark widgets"
```

---

### Task 3: Theme Tokens And Mist Backdrop

**Files:**
- Modify: `apps/rain/lib/presentation/theme/rain_theme.dart`
- Modify: `apps/rain/lib/presentation/widgets/rain_backdrop.dart`
- Modify: `apps/rain/test/rain_theme_test.dart`

- [ ] **Step 1: Add brand color aliases**

Add these constants to `RainColors`:

```dart
static const Color mistCyan = Color(0xFF7DEBFF);
static const Color peerMint = Color(0xFF2DD4A3);
static const Color quietLine = Color(0xFF28424D);
static const Color errorCoral = Color(0xFFFF6B6B);
```

Keep existing colors until all references are migrated.

- [ ] **Step 2: Replace glow blobs with mist/signal painter**

In `rain_backdrop.dart`, replace `_RainAtmosphere` and `_GlowBlob` with a `CustomPaint` painter that draws restrained diagonal lines and faint wave arcs:

```dart
class _RainAtmosphere extends StatelessWidget {
  const _RainAtmosphere({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RainSignalMistPainter(isDark: isDark),
        child: const SizedBox.expand(),
      ),
    );
  }
}
```

Use `RainColors.mistCyan` at low opacity and avoid radial glow blobs.

- [ ] **Step 3: Update backdrop test**

Extend `apps/rain/test/rain_theme_test.dart` so it asserts `RainBackdrop` still follows light theme surfaces and renders a `CustomPaint` atmosphere:

```dart
expect(find.byType(CustomPaint), findsWidgets);
```

- [ ] **Step 4: Validate Task 3**

```powershell
cd apps/rain
flutter test test/rain_theme_test.dart
```

Expected: theme/backdrop tests pass.

- [ ] **Step 5: Commit Task 3**

```powershell
git add apps/rain/lib/presentation/theme/rain_theme.dart apps/rain/lib/presentation/widgets/rain_backdrop.dart apps/rain/test/rain_theme_test.dart
git commit -m "feat: apply Signal Mist theme backdrop"
```

---

### Task 4: Splash And Header Rebrand

**Files:**
- Modify: `apps/rain/lib/presentation/screens/splash_screen.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/shell_header.dart`
- Modify: `apps/rain/test/root_screen_test.dart`
- Modify: `apps/rain/test/onboarding_screen_test.dart` if header assumptions break

- [ ] **Step 1: Replace splash icon and remove loading bar**

In `splash_screen.dart`:

- import `rain_peer_core_mark.dart`
- replace the PNG container with `RainPeerCoreAnimatedMark(size: 112)`
- change subtitle to `Private peer link`
- remove the `LinearProgressIndicator`

Use this structure:

```dart
const RainPeerCoreAnimatedMark(size: 112),
const SizedBox(height: 22),
Text(title, textAlign: TextAlign.center, style: ...),
const SizedBox(height: 8),
Text(subtitle, textAlign: TextAlign.center, style: ...),
```

- [ ] **Step 2: Replace shell header logo**

In `shell_header.dart`, replace `Image.asset('assets/branding/rain_app_icon_1024.png')` fallback with:

```dart
RainPeerCoreMark(size: size * 0.72, useTinyVariant: size < 44)
```

Keep the same container size and layout.

- [ ] **Step 3: Add splash test assertion**

In `apps/rain/test/root_screen_test.dart`, update loading-state test to assert:

```dart
expect(find.text('Rain'), findsOneWidget);
expect(find.text('Private peer link'), findsOneWidget);
expect(find.byType(LinearProgressIndicator), findsNothing);
```

- [ ] **Step 4: Validate Task 4**

```powershell
cd apps/rain
flutter test test/root_screen_test.dart test/onboarding_screen_test.dart
```

Expected: tests pass with no splash loading bar.

- [ ] **Step 5: Commit Task 4**

```powershell
git add apps/rain/lib/presentation/screens/splash_screen.dart apps/rain/lib/presentation/widgets/home/shell_header.dart apps/rain/test/root_screen_test.dart apps/rain/test/onboarding_screen_test.dart
git commit -m "feat: rebrand Rain splash and shell header"
```

---

### Task 5: Mist State Cards And Rain Loading Skeletons

**Files:**
- Create: `apps/rain/lib/presentation/branding/rain_state_surfaces.dart`
- Create: `apps/rain/test/rain_state_surfaces_test.dart`
- Modify: `apps/rain/lib/presentation/widgets/app_components.dart`
- Modify: state call sites in `friends_list.dart`, `chat_panel.dart`, `search_screen.dart`, `root_screen.dart`, `settings_screen.dart`

- [ ] **Step 1: Add `RainMistStateCard` and `RainStreakSkeleton`**

Create `rain_state_surfaces.dart` with:

```dart
import 'package:flutter/material.dart';

import '../theme/rain_theme.dart';

class RainMistStateCard extends StatelessWidget {
  const RainMistStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.action,
    this.severity = RainStateSeverity.neutral,
    this.compact = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final Widget? action;
  final RainStateSeverity severity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (severity) {
      RainStateSeverity.neutral => RainColors.mistCyan,
      RainStateSeverity.warning => RainColors.warning,
      RainStateSeverity.error => RainColors.errorCoral,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, color: accent, size: compact ? 28 : 40),
                  const SizedBox(height: 12),
                ],
                Text(title, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                if (action != null) ...<Widget>[const SizedBox(height: 16), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum RainStateSeverity { neutral, warning, error }

class RainStreakSkeleton extends StatelessWidget {
  const RainStreakSkeleton({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(rows, (index) {
        final width = switch (index % 3) {
          0 => 0.72,
          1 => 0.96,
          _ => 0.48,
        };
        return FractionallySizedBox(
          widthFactor: width,
          alignment: Alignment.centerLeft,
          child: Container(
            key: ValueKey<String>('rain_streak_skeleton_row_$index'),
            height: 12,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: RainColors.mistCyan.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}
```

- [ ] **Step 2: Bridge `AppStateMessage` to Mist State Card**

In `app_components.dart`, import `rain_state_surfaces.dart` and make `AppStateMessage.build` return `RainMistStateCard` with compatible parameters. Map `iconColor == scheme.error` to `RainStateSeverity.error`.

- [ ] **Step 3: Replace full-screen loading spinners where context exists**

Use `RainStreakSkeleton` in:

- `friends_list.dart` loading branch
- `chat_panel.dart` messages loading branch
- `search_screen.dart` `_SearchLoading`
- settings async rows where skeleton fits better than spinner

Keep tiny `CircularProgressIndicator(strokeWidth: 2)` inside buttons during active submit/send operations.

- [ ] **Step 4: Add state surface tests**

Create `apps/rain/test/rain_state_surfaces_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';

void main() {
  testWidgets('RainMistStateCard renders title message and action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RainMistStateCard(
          title: 'No messages yet',
          message: 'Start the first message when the link is ready.',
          icon: Icons.chat_bubble_outline,
          action: TextButton(onPressed: () {}, child: const Text('Message')),
        ),
      ),
    );

    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.text('Start the first message when the link is ready.'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('RainStreakSkeleton renders requested rows', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RainStreakSkeleton(rows: 4)),
    );

    for (var index = 0; index < 4; index += 1) {
      expect(
        find.byKey(ValueKey<String>('rain_streak_skeleton_row_$index')),
        findsOneWidget,
      );
    }
  });
}
```

- [ ] **Step 5: Validate Task 5**

```powershell
cd apps/rain
flutter test test/rain_state_surfaces_test.dart test/search_screen_test.dart test/friend_flow_test.dart test/root_screen_test.dart
```

Expected: focused state-surface tests pass.

- [ ] **Step 6: Commit Task 5**

```powershell
git add apps/rain/lib/presentation/branding/rain_state_surfaces.dart apps/rain/lib/presentation/widgets/app_components.dart apps/rain/lib/presentation/widgets/home/friends_list.dart apps/rain/lib/presentation/widgets/home/chat_panel.dart apps/rain/lib/presentation/screens/search_screen.dart apps/rain/lib/presentation/screens/root_screen.dart apps/rain/lib/presentation/screens/settings_screen.dart apps/rain/test/rain_state_surfaces_test.dart apps/rain/test/search_screen_test.dart apps/rain/test/friend_flow_test.dart apps/rain/test/root_screen_test.dart
git commit -m "feat: add Rain mist state surfaces"
```

---

### Task 6: Rain Streak Active-State Treatment

**Files:**
- Create: `apps/rain/lib/presentation/branding/rain_streak_surface.dart`
- Modify: `apps/rain/lib/presentation/navigation/rain_navigation_shell.dart`
- Modify: `apps/rain/lib/presentation/widgets/chat_composer.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/link_status.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: related widget tests

- [ ] **Step 1: Add `RainStreakSurface`**

Create `rain_streak_surface.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/rain_theme.dart';

class RainStreakSurface extends StatelessWidget {
  const RainStreakSurface({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _RainStreakPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _RainStreakPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (var x = -size.width; x < size.width * 2; x += 18) {
      canvas.drawLine(
        Offset(x.toDouble(), -size.height * 0.2),
        Offset(x + size.width * 0.20, size.height * 1.2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RainStreakPainter oldDelegate) => false;
}
```

- [ ] **Step 2: Apply only to active/primary/state surfaces**

Wrap, do not replace, existing controls:

- selected navigation icon/indicator in `rain_navigation_shell.dart`
- send button in `chat_composer.dart`
- direct/relay/connecting status chips in `link_status.dart`
- active call controls in `rain_call_controls.dart`

Neutral icon buttons remain unwrapped.

- [ ] **Step 3: Add focused assertions**

Update tests to assert selected/primary states render `RainStreakSurface`:

```dart
expect(find.byType(RainStreakSurface), findsWidgets);
```

Add imports where needed.

- [ ] **Step 4: Validate Task 6**

```powershell
cd apps/rain
flutter test test/rain_navigation_shell_test.dart test/chat_composer_test.dart test/rain_chat_widgets_test.dart test/call_surface_providers_test.dart
```

Expected: active-state treatment tests pass.

- [ ] **Step 5: Commit Task 6**

```powershell
git add apps/rain/lib/presentation/branding/rain_streak_surface.dart apps/rain/lib/presentation/navigation/rain_navigation_shell.dart apps/rain/lib/presentation/widgets/chat_composer.dart apps/rain/lib/presentation/widgets/home/link_status.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/test/rain_navigation_shell_test.dart apps/rain/test/chat_composer_test.dart apps/rain/test/rain_chat_widgets_test.dart apps/rain/test/call_surface_providers_test.dart
git commit -m "feat: add Rain Streak active states"
```

---

### Task 7: Conversation, File Transfer, And Call Polish

**Files:**
- Modify: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/file_transfer_bubble.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: related tests

- [ ] **Step 1: Apply Mist State Card to chat empty/failure**

In `chat_panel.dart`, replace the `No messages yet` `AppStateMessage` call with the bridged Mist State Card behavior. Keep text:

```dart
title: 'No messages yet',
message: 'Start the first message when the link is ready.',
```

- [ ] **Step 2: Apply Rain brand to file transfer states**

In `file_transfer_bubble.dart`, keep existing file actions but use:

- `RainColors.mistCyan` for in-progress
- `RainColors.peerMint` for complete
- `RainColors.warning` for waiting
- `RainColors.errorCoral` for failed

Do not animate file progress continuously. Use existing progress semantics.

- [ ] **Step 3: Apply Peer Core status to call overlay**

In `rain_call_overlay.dart`, use `RainPeerCoreAnimatedMark` for connecting/ringing state glyph surfaces. For failed state, keep clear error styling and retry.

- [ ] **Step 4: Validate workflow widgets**

```powershell
cd apps/rain
flutter test test/rain_chat_widgets_test.dart test/file_transfer_progress_batcher_test.dart test/video_call_renderers_test.dart test/voice_audio_level_test.dart
```

Expected: chat, file-transfer, and call-surface tests pass.

- [ ] **Step 5: Commit Task 7**

```powershell
git add apps/rain/lib/presentation/widgets/home/chat_panel.dart apps/rain/lib/presentation/widgets/home/file_transfer_bubble.dart apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/test/rain_chat_widgets_test.dart apps/rain/test/file_transfer_progress_batcher_test.dart apps/rain/test/video_call_renderers_test.dart apps/rain/test/voice_audio_level_test.dart
git commit -m "feat: polish Rain conversation and call surfaces"
```

---

### Task 8: Platform Icon Preparation

**Files:**
- Modify after approval: Android, Windows, Linux, and macOS icon files
- Create if useful: `scripts/generate_rain_platform_icons.ps1`

- [ ] **Step 1: Defer platform replacement until in-app approval**

Do not replace platform icons until the app-shell mark, splash mark, and state treatment are approved in the running app.

- [ ] **Step 2: Use generated approved source**

Use:

```text
apps/rain/assets/branding/generated/peer_core_app_icon_1024.png
```

as the canonical platform icon source after approval.

- [ ] **Step 3: Replace platform icon targets**

Targets:

```text
apps/rain/android/app/src/main/res/mipmap-mdpi/ic_launcher.png
apps/rain/android/app/src/main/res/mipmap-hdpi/ic_launcher.png
apps/rain/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
apps/rain/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
apps/rain/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
apps/rain/linux/runner/resources/app_icon.png
apps/rain/windows/runner/resources/app_icon.ico
apps/rain/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png
apps/rain/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png
apps/rain/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png
apps/rain/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png
apps/rain/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png
apps/rain/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png
apps/rain/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png
```

- [ ] **Step 4: Validate asset legibility**

Inspect:

```text
apps/rain/assets/branding/generated/peer_core_preview_sheet.png
apps/rain/assets/branding/generated/peer_core_size_check.png
```

Expected: 16 and 24 px variants use simplified ring+dot; 48 px and larger can carry the peer-node triangle.

- [ ] **Step 5: Commit Task 8**

```powershell
git add apps/rain/android/app/src/main/res apps/rain/linux/runner/resources apps/rain/windows/runner/resources apps/rain/macos/Runner/Assets.xcassets
git commit -m "feat: update Rain platform icons"
```

---

### Task 9: Full Validation Gate

**Files:**
- Modify: docs if QA notes are added

- [ ] **Step 1: Run normal validation**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

Expected: all checks pass.

- [ ] **Step 2: Manual visual pass**

Run the app on Windows:

```powershell
cd apps/rain
flutter run -d windows --dart-define=RAIN_BACKEND=noop
```

Inspect:

- splash has no loading bar
- Peer Core mark renders
- home header mark renders
- active nav item has Rain Streak treatment
- empty states use Mist State Cards
- loading states use skeletons where context exists
- chat remains dense and readable
- call controls remain obvious

- [ ] **Step 3: Commit QA note if needed**

If visual QA notes are created:

```powershell
git add docs/qa
git commit -m "docs: record Rain rebrand visual QA"
```

---

## Plan Self-Review

- Covers all locked brainstorm decisions: Signal Mist, Peer Core, no splash loading bar, Rain Streak active states, Mist State Cards, animation-ready layers, and Ink/Mist/Mint palette.
- Keeps source assets out of runtime bundle by introducing runtime asset copies and narrowed `pubspec.yaml` entries.
- Avoids a full custom icon set.
- Keeps motion event-bound.
- Defers platform icon replacement until the in-app mark is approved.
- Uses normal project validation commands from `AGENTS.md`.
