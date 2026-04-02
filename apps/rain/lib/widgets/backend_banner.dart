import 'package:flutter/material.dart';

import '../theme/rain_theme.dart';

class BackendBanner extends StatelessWidget {
  const BackendBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: RainColors.tertiary.withValues(alpha: 0.16),
      child: Text(message, style: const TextStyle(color: Color(0xFFFFE0A3))),
    );
  }
}
