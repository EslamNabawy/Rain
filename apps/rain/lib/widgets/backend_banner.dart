import 'package:flutter/material.dart';

class BackendBanner extends StatelessWidget {
  const BackendBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: const Color(0xFF2A2010),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFFFD89B)),
      ),
    );
  }
}
