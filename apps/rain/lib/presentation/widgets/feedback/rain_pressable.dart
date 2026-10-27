/// # rain_pressable.dart
///
/// Press, hover and keyboard-focus feedback. Wrapping an already interactive
/// child (IconButton, InkWell) without [RainPressable.onTap] adds only the
/// 0.97 press scale. With [RainPressable.onTap] it is a full control: tap,
/// Enter/Space activation, a desktop hover overlay and a visible focus ring.
///
/// **Key types:** RainPressable
///
/// **Depends on:** RainMotion, RainRadius, RainMotionPolicy
library;

import 'package:material_ui/material_ui.dart';

import 'package:rain/presentation/performance/rain_motion_policy.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

class RainPressable extends StatefulWidget {
  const RainPressable({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool autofocus;

  @override
  State<RainPressable> createState() => _RainPressableState();
}

class _RainPressableState extends State<RainPressable> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = RainMotionPolicy.of(context);
    Widget result = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !policy.reduced ? 0.97 : 1,
        duration: policy.d(RainMotion.pressScale),
        curve: RainMotion.enter,
        child: widget.child,
      ),
    );
    final onTap = widget.onTap;
    if (onTap == null) {
      return result;
    }
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(RainRadius.md);
    result = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: _hovered ? scheme.onSurface.withValues(alpha: 0.06) : null,
        border: _focused ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: result,
    );
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (bool value) => setState(() => _focused = value),
        onShowHoverHighlight: (bool value) => setState(() => _hovered = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: result,
        ),
      ),
    );
  }
}
