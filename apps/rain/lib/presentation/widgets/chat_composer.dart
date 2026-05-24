import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rain/presentation/branding/rain_streak_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.maxLength,
    required this.onSend,
    this.onAttach,
    this.isAttaching = false,
    this.hintText = 'Message',
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final int maxLength;
  final FutureOr<void> Function() onSend;
  final FutureOr<void> Function()? onAttach;
  final bool isAttaching;
  final String hintText;
  final TextCapitalization textCapitalization;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'ChatComposer',
    onKeyEvent: _handleKeyEvent,
  );

  bool get _canSend =>
      widget.enabled &&
      !widget.isSending &&
      widget.controller.text.trim().isNotEmpty;

  bool get _canAttach =>
      widget.enabled && !widget.isSending && !widget.isAttaching;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleComposerChanged);
    _focusNode.addListener(_handleComposerChanged);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleComposerChanged);
      widget.controller.addListener(_handleComposerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleComposerChanged);
    _focusNode.removeListener(_handleComposerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isDesktopPlatform) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }

    unawaited(_submit());
    return KeyEventResult.handled;
  }

  bool get _isDesktopPlatform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => false,
    };
  }

  Future<void> _submit() async {
    if (!_canSend) {
      if (mounted && widget.enabled) {
        _focusNode.requestFocus();
      }
      return;
    }

    await Future<void>.sync(widget.onSend);
    if (mounted && widget.enabled) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final inputFill = isDark
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.70)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.86);
    final borderColor = _focusNode.hasFocus
        ? scheme.primary.withValues(alpha: 0.62)
        : scheme.outlineVariant.withValues(alpha: isDark ? 0.28 : 0.70);

    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (widget.onAttach != null) ...<Widget>[
            SizedBox.square(
              dimension: 48,
              child: IconButton.filledTonal(
                tooltip: 'Attach file',
                onPressed: _canAttach
                    ? () => unawaited(Future<void>.sync(widget.onAttach!))
                    : null,
                icon: widget.isAttaching
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    : const Icon(Icons.attach_file_rounded),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: AnimatedContainer(
              duration: RainMotion.quick,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: inputFill,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor),
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                maxLength: widget.maxLength,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                textCapitalization: widget.textCapitalization,
                onSubmitted: (_) => unawaited(_submit()),
                mouseCursor: SystemMouseCursors.text,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  counterText: '',
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  suffixIcon: widget.controller.text.length > 3800
                      ? Icon(
                          Icons.warning_amber_rounded,
                          color: scheme.error,
                          size: 20,
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 48,
            child: RainStreakSurface(
              enabled: _canSend || widget.isSending,
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              child: FilledButton(
                onPressed: _canSend ? () => unawaited(_submit()) : null,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                child: widget.isSending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
