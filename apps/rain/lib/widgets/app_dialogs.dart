import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  ButtonStyle? confirmStyle,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: confirmStyle,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

Future<String?> showAppTextInputDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  String? initialValue,
  String? labelText,
  String? hintText,
  String? helperText,
  int? maxLength,
  bool obscureText = false,
  bool autofocus = true,
  TextInputAction textInputAction = TextInputAction.done,
  List<TextInputFormatter>? inputFormatters,
  int? minLines,
  int? maxLines,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return _AppTextInputDialog(
        title: title,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        initialValue: initialValue,
        labelText: labelText,
        hintText: hintText,
        helperText: helperText,
        maxLength: maxLength,
        obscureText: obscureText,
        autofocus: autofocus,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        minLines: minLines,
        maxLines: maxLines,
      );
    },
  );
}

class _AppTextInputDialog extends StatefulWidget {
  const _AppTextInputDialog({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.initialValue,
    required this.labelText,
    required this.hintText,
    required this.helperText,
    required this.maxLength,
    required this.obscureText,
    required this.autofocus,
    required this.textInputAction,
    required this.inputFormatters,
    required this.minLines,
    required this.maxLines,
  });

  final String title;
  final String confirmLabel;
  final String cancelLabel;
  final String? initialValue;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final int? maxLength;
  final bool obscureText;
  final bool autofocus;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int? maxLines;

  @override
  State<_AppTextInputDialog> createState() => _AppTextInputDialogState();
}

class _AppTextInputDialogState extends State<_AppTextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        textInputAction: widget.textInputAction,
        inputFormatters: widget.inputFormatters,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          helperText: widget.helperText,
          counterText: '',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
