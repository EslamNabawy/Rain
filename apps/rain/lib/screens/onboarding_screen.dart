import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import '../providers/app_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        final cardPadding = constraints.maxWidth < 420 ? 20.0 : 32.0;

        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  elevation: 16,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(cardPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'RAIN',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Peer-to-peer chat for desktop and Android. Choose your identity to start wiring the backend and local stores together.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            hintText: 'lowercase, numbers, underscores',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _displayNameController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: constraints.maxWidth < 420
                              ? double.infinity
                              : null,
                          child: FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: Text(
                              _submitting
                                  ? 'Creating profile...'
                                  : 'Create identity',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final adapter = ref.read(adapterProvider);
    final identityRepository = ref.read(identityRepositoryProvider);
    final username = _usernameController.text.trim().toLowerCase();
    final displayName = _displayNameController.text.trim().isEmpty
        ? username
        : _displayNameController.text.trim();

    if (!RainIdentity.isValidUsername(username)) {
      setState(() {
        _error = 'Use 3-24 lowercase letters, numbers, or underscores.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await adapter.ensureAuthenticated();
      final currentUid = await adapter.currentUid();
      final existing = await adapter.fetchIdentity(username);
      if (existing != null && existing.uid != currentUid) {
        setState(() {
          _error = 'That username is already taken.';
          _submitting = false;
        });
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final identity = RainIdentity(
        username: username,
        displayName: displayName,
        createdAt: now,
      );
      await adapter.upsertIdentity(
        BackendIdentity(
          username: username,
          uid: currentUid,
          displayName: displayName,
          registeredAt: now,
          lastSeen: now,
          lastHeartbeat: now,
          online: true,
        ),
      );
      await identityRepository.saveIdentity(identity);
      await adapter.setPresence(username, true);
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}
