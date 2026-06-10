import 'package:flutter/material.dart';

import 'package:rain/infrastructure/services/force_update_service.dart';

class RainUpdatePromptBanner extends StatelessWidget {
  const RainUpdatePromptBanner({
    super.key,
    required this.result,
    required this.onUpdate,
    required this.onDismiss,
  });

  final VersionCheckResult result;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = result.displayLatestVersion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.30)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.system_update_alt, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rain $latest is available.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
              TextButton(onPressed: onUpdate, child: const Text('Update')),
              IconButton(
                tooltip: 'Dismiss update',
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
