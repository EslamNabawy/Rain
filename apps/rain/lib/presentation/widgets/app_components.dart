import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin,
    this.elevation = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation,
      margin: margin,
      child: Padding(padding: padding, child: child),
    );
  }
}

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.only(left: 4, bottom: 8),
  });

  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class AppPageFrame extends StatelessWidget {
  const AppPageFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.actions = const <Widget>[],
  });

  final String title;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = constraints.maxWidth < 700;
        final padding = EdgeInsets.all(isCompact ? 12 : 20);

        return SafeArea(
          child: Padding(
            padding: padding,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0C1820).withValues(alpha: 0.94)
                    : scheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(
                    alpha: isDark ? 0.18 : 0.55,
                  ),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    blurRadius: isDark ? 32 : 18,
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.08),
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isCompact ? 18 : 24,
                      isCompact ? 18 : 24,
                      isCompact ? 18 : 24,
                      14,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(icon, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        ...actions,
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AppStateMessage extends StatelessWidget {
  const AppStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.iconSize = 52,
    this.padding = const EdgeInsets.all(24),
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: iconSize,
              color: iconColor ?? Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class AppLowerCaseTextFormatter extends TextInputFormatter {
  const AppLowerCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toLowerCase(),
      selection: newValue.selection,
    );
  }
}

class AppTextInputField extends StatefulWidget {
  const AppTextInputField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.helperText,
    this.maxLength,
    this.textInputAction,
    this.textInputType,
    this.obscureText = false,
    this.autofocus = false,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.minLines,
    this.maxLines,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextInputType? textInputType;
  final bool obscureText;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? minLines;
  final int? maxLines;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool autocorrect;
  final bool enableSuggestions;
  final EdgeInsets scrollPadding;

  @override
  State<AppTextInputField> createState() => _AppTextInputFieldState();
}

class _AppTextInputFieldState extends State<AppTextInputField> {
  FocusNode? _internalFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode!;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode == null ? FocusNode() : null;
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      textInputAction: widget.textInputAction,
      keyboardType: widget.textInputType,
      inputFormatters: widget.inputFormatters,
      minLines: widget.minLines,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      textCapitalization: widget.textCapitalization,
      autofillHints: widget.autofillHints,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      scrollPadding: widget.scrollPadding,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      mouseCursor: SystemMouseCursors.text,
      onTap: () {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      },
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        helperText: widget.helperText,
        counterText: '',
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 56,
          minHeight: 56,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 56,
          minHeight: 56,
        ),
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.suffixIcon,
      ),
    );
  }
}
