import 'package:flutter/material.dart';

class BackendBanner extends StatelessWidget {
  const BackendBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: const Color(0xFFFFF1D6),
      child: Text(message),
    );
  }
}
