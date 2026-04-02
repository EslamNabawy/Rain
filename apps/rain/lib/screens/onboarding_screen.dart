import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import '../providers/app_providers.dart';
import '../widgets/app_components.dart';

enum _AuthMode { register, login }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.register;
  RainGender _gender = RainGender.male;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    if (_mode == mode) {
      return;
    }

    setState(() {
      _mode = mode;
      _error = null;
      if (mode == _AuthMode.login) {
        _displayNameController.clear();
      }
    });
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
                          'Peer-to-peer chat for desktop and Android.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),
                        _buildModeToggle(),
                        const SizedBox(height: 20),
                        AppTextInputField(
                          controller: _usernameController,
                          labelText: 'Username',
                          hintText: 'lowercase, numbers, underscores',
                          maxLength: InputValidator.usernameMaxLength,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-z0-9_]'),
                            ),
                            const AppLowerCaseTextFormatter(),
                          ],
                        ),
                        if (_mode == _AuthMode.register) ...<Widget>[
                          const SizedBox(height: 16),
                          AppTextInputField(
                            controller: _displayNameController,
                            labelText: 'Display name',
                            textInputAction: TextInputAction.next,
                            maxLength: InputValidator.displayNameMaxLength,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<RainGender>(
                            value: _gender,
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                            ),
                            items: const <DropdownMenuItem<RainGender>>[
                              DropdownMenuItem<RainGender>(
                                value: RainGender.male,
                                child: Text('Male'),
                              ),
                              DropdownMenuItem<RainGender>(
                                value: RainGender.female,
                                child: Text('Female'),
                              ),
                            ],
                            onChanged: (RainGender? value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _gender = value;
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        AppTextInputField(
                          controller: _passwordController,
                          labelText: 'Password',
                          hintText: 'at least 6 characters',
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          maxLength: 50,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
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
                                  ? (_mode == _AuthMode.register
                                        ? 'Creating account...'
                                        : 'Signing in...')
                                  : (_mode == _AuthMode.register
                                        ? 'Create account'
                                        : 'Sign in'),
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

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: () => _setMode(_AuthMode.register),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _mode == _AuthMode.register
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Register',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _mode == _AuthMode.register ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _setMode(_AuthMode.login),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _mode == _AuthMode.login
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Login',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _mode == _AuthMode.login ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final adapter = ref.read(adapterProvider);
    final identityRepository = ref.read(identityRepositoryProvider);
    final username = InputValidator.normalizeUsername(_usernameController.text);
    final password = _passwordController.text;

    final usernameError = InputValidator.usernameError(username);
    if (usernameError != null) {
      setState(() => _error = usernameError);
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    if (password.length > 50) {
      setState(() => _error = 'Password must be at most 50 characters');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      late RainIdentity identity;
      late String displayName;

      if (_mode == _AuthMode.register) {
        final rawDisplayName = _displayNameController.text.trim();
        displayName = rawDisplayName.isEmpty
            ? username
            : InputValidator.normalizeDisplayName(rawDisplayName);

        final displayNameError = InputValidator.displayNameError(displayName);
        if (displayNameError != null) {
          setState(() => _error = displayNameError);
          return;
        }

        await adapter.register(username, password);
        final now = DateTime.now().millisecondsSinceEpoch;
        identity = RainIdentity(
          username: username,
          displayName: displayName,
          createdAt: now,
          gender: _gender,
        );
      } else {
        await adapter.login(username, password);
        final existing = await adapter.fetchIdentity(username);
        displayName = existing?.displayName ?? username;
        identity = RainIdentity(
          username: username,
          displayName: displayName,
          createdAt:
              existing?.registeredAt ?? DateTime.now().millisecondsSinceEpoch,
          gender: existing?.gender == null
              ? null
              : RainGender.values.byName(existing!.gender!),
        );
      }

      await adapter.addToUserSearch(username);
      await identityRepository.saveIdentity(identity);
      await adapter.upsertIdentity(
        BackendIdentity(
          username: identity.username,
          uid: await adapter.currentUid(),
          displayName: identity.displayName,
          gender: identity.gender?.name,
          registeredAt: identity.createdAt,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
          lastHeartbeat: DateTime.now().millisecondsSinceEpoch,
          online: true,
        ),
      );
      await adapter.setPresence(username, true);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
