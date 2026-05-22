import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/app_components.dart';

enum _AuthMode { register, login }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _usernameFocusNode = FocusNode(debugLabel: 'Username');
  final FocusNode _displayNameFocusNode = FocusNode(debugLabel: 'DisplayName');
  final FocusNode _passwordFocusNode = FocusNode(debugLabel: 'Password');
  final GlobalKey _usernameFieldKey = GlobalKey();
  final GlobalKey _displayNameFieldKey = GlobalKey();
  final GlobalKey _passwordFieldKey = GlobalKey();
  final Set<Timer> _revealTimers = <Timer>{};
  _AuthMode _mode = _AuthMode.login;
  RainGender _gender = RainGender.male;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usernameFocusNode.addListener(
      () => _ensureFocusedFieldVisible(_usernameFocusNode, _usernameFieldKey),
    );
    _displayNameFocusNode.addListener(
      () => _ensureFocusedFieldVisible(
        _displayNameFocusNode,
        _displayNameFieldKey,
      ),
    );
    _passwordFocusNode.addListener(
      () => _ensureFocusedFieldVisible(_passwordFocusNode, _passwordFieldKey),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _revealTimers) {
      timer.cancel();
    }
    _revealTimers.clear();
    _usernameFocusNode.dispose();
    _displayNameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _scrollController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _ensureVisibleForFocusedField();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureVisibleForFocusedField();
    });
  }

  void _ensureFocusedFieldVisible(FocusNode focusNode, GlobalKey key) {
    if (!focusNode.hasFocus) {
      return;
    }
    _scheduleFocusedFieldReveal(focusNode, key);
    _scheduleFocusedFieldReveal(
      focusNode,
      key,
      delay: const Duration(milliseconds: 120),
    );
    _scheduleFocusedFieldReveal(focusNode, key, delay: RainMotion.standard);
    _scheduleFocusedFieldReveal(
      focusNode,
      key,
      delay: const Duration(milliseconds: 520),
    );
  }

  void _scheduleFocusedFieldReveal(
    FocusNode focusNode,
    GlobalKey key, {
    Duration delay = Duration.zero,
  }) {
    if (delay == Duration.zero) {
      _revealFocusedField(focusNode, key);
      return;
    }

    late final Timer timer;
    timer = Timer(delay, () {
      _revealTimers.remove(timer);
      _revealFocusedField(focusNode, key);
    });
    _revealTimers.add(timer);
  }

  void _revealFocusedField(FocusNode focusNode, GlobalKey key) {
    if (!mounted || !focusNode.hasFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.hasFocus) {
        return;
      }
      final fieldContext = key.currentContext;
      if (fieldContext == null) {
        return;
      }
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      Scrollable.ensureVisible(
        fieldContext,
        duration: RainMotion.standard,
        curve: Curves.easeOutCubic,
        alignment: keyboardOpen ? 0.08 : 0,
        alignmentPolicy: keyboardOpen
            ? ScrollPositionAlignmentPolicy.explicit
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  void _ensureVisibleForFocusedField() {
    if (_usernameFocusNode.hasFocus) {
      _ensureFocusedFieldVisible(_usernameFocusNode, _usernameFieldKey);
    } else if (_displayNameFocusNode.hasFocus) {
      _ensureFocusedFieldVisible(_displayNameFocusNode, _displayNameFieldKey);
    } else if (_passwordFocusNode.hasFocus) {
      _ensureFocusedFieldVisible(_passwordFocusNode, _passwordFieldKey);
    }
  }

  String _formatError(Object error) {
    final raw = error.toString().trim();
    const prefixes = <String>['Exception: ', 'Bad state: '];
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        return raw.substring(prefix.length).trim();
      }
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final networkStatus = ref.watch(networkStatusProvider).value;
    final networkBlocked = networkStatus?.blocksNetworkActions ?? false;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final scheme = Theme.of(context).colorScheme;
        final isDark = scheme.brightness == Brightness.dark;
        final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardOpen = keyboardBottom > 0;
        final isTightHeight = constraints.maxHeight < 680 || keyboardOpen;
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        final cardPadding = isTightHeight
            ? (keyboardOpen ? 14.0 : 18.0)
            : (constraints.maxWidth < 420 ? 20.0 : 32.0);
        final verticalPadding = keyboardOpen ? 6.0 : 24.0;
        final fieldGap = keyboardOpen ? 12.0 : 16.0;
        final sectionGap = keyboardOpen ? 12.0 : (isTightHeight ? 18.0 : 24.0);
        final showBrandHeader = !keyboardOpen;
        final fieldScrollPadding = EdgeInsets.fromLTRB(
          20,
          20,
          20,
          keyboardBottom + 120,
        );

        return SafeArea(
          child: Align(
            alignment: isTightHeight ? Alignment.topCenter : Alignment.center,
            child: SingleChildScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                verticalPadding,
                horizontalPadding,
                verticalPadding + keyboardBottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  elevation: isDark ? 0 : 16,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(cardPadding),
                    child: AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (showBrandHeader) ...<Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  width: 44,
                                  height: 44,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    'assets/branding/rain_app_icon_1024.png',
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.hub_outlined,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'Rain',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Peer-to-peer chat for desktop and Android.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: sectionGap),
                          ],
                          Text(
                            _mode == _AuthMode.login
                                ? 'Sign in'
                                : 'Create account',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: fieldGap),
                          if (_mode == _AuthMode.register) ...<Widget>[
                            KeyedSubtree(
                              key: _displayNameFieldKey,
                              child: AppTextInputField(
                                controller: _displayNameController,
                                focusNode: _displayNameFocusNode,
                                labelText: 'Display name',
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                maxLength: InputValidator.displayNameMaxLength,
                                autofillHints: const <String>[
                                  AutofillHints.name,
                                ],
                                scrollPadding: fieldScrollPadding,
                                prefixIcon: const Icon(Icons.badge_outlined),
                                onSubmitted: (_) =>
                                    _usernameFocusNode.requestFocus(),
                              ),
                            ),
                            SizedBox(height: fieldGap),
                          ],
                          KeyedSubtree(
                            key: _usernameFieldKey,
                            child: AppTextInputField(
                              controller: _usernameController,
                              focusNode: _usernameFocusNode,
                              labelText: _mode == _AuthMode.register
                                  ? 'Unique Username'
                                  : 'Username',
                              hintText: _mode == _AuthMode.register
                                  ? 'Unique Username'
                                  : null,
                              maxLength: InputValidator.usernameMaxLength,
                              textInputAction: TextInputAction.next,
                              textInputType: TextInputType.visiblePassword,
                              autofillHints: const <String>[
                                AutofillHints.username,
                              ],
                              scrollPadding: fieldScrollPadding,
                              autocorrect: false,
                              enableSuggestions: false,
                              prefixIcon: const Icon(Icons.alternate_email),
                              onSubmitted: (_) {
                                _passwordFocusNode.requestFocus();
                              },
                              inputFormatters: [
                                const AppLowerCaseTextFormatter(),
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-z0-9_]'),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: fieldGap),
                          KeyedSubtree(
                            key: _passwordFieldKey,
                            child: AppTextInputField(
                              controller: _passwordController,
                              focusNode: _passwordFocusNode,
                              labelText: 'Password',
                              hintText: _mode == _AuthMode.register
                                  ? 'at least 6 characters'
                                  : null,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              maxLength: 50,
                              autofillHints: <String>[
                                _mode == _AuthMode.register
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              scrollPadding: fieldScrollPadding,
                              autocorrect: false,
                              enableSuggestions: false,
                              prefixIcon: const Icon(Icons.lock_outline),
                              onSubmitted: (_) {
                                if (!_submitting) {
                                  _submit();
                                }
                              },
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
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
                          ),
                          if (_mode == _AuthMode.register) ...<Widget>[
                            SizedBox(height: fieldGap),
                            Text(
                              'Gender',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<RainGender>(
                                segments: const <ButtonSegment<RainGender>>[
                                  ButtonSegment<RainGender>(
                                    value: RainGender.male,
                                    icon: Icon(Icons.male),
                                    label: Text('Male'),
                                  ),
                                  ButtonSegment<RainGender>(
                                    value: RainGender.female,
                                    icon: Icon(Icons.female),
                                    label: Text('Female'),
                                  ),
                                ],
                                selected: <RainGender>{_gender},
                                onSelectionChanged:
                                    (Set<RainGender> selection) {
                                      setState(() {
                                        _gender = selection.first;
                                      });
                                    },
                              ),
                            ),
                          ],
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(color: scheme.error),
                            ),
                          ],
                          SizedBox(height: sectionGap),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _submitting || networkBlocked
                                  ? null
                                  : _submit,
                              icon: _submitting
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onPrimary,
                                      ),
                                    )
                                  : Icon(
                                      _mode == _AuthMode.register
                                          ? Icons.person_add_alt_1
                                          : Icons.login,
                                    ),
                              label: Text(
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
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => _setMode(
                                      _mode == _AuthMode.login
                                          ? _AuthMode.register
                                          : _AuthMode.login,
                                    ),
                              child: Text(
                                _mode == _AuthMode.login
                                    ? 'Create account'
                                    : 'Sign in',
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
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final networkStatus = ref.read(networkStatusProvider).value;
    if (networkStatus != null && networkStatus.blocksNetworkActions) {
      setState(() => _error = networkStatus.actionErrorMessage);
      _playSound(RainSoundEffect.error);
      return;
    }

    final username = InputValidator.normalizeUsername(_usernameController.text);
    final password = _passwordController.text;

    final usernameError = InputValidator.usernameError(username);
    if (usernameError != null) {
      setState(() => _error = usernameError);
      _playSound(RainSoundEffect.error);
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      _playSound(RainSoundEffect.error);
      return;
    }

    if (password.length > 50) {
      setState(() => _error = 'Password must be at most 50 characters');
      _playSound(RainSoundEffect.error);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_mode == _AuthMode.register) {
        final rawDisplayName = _displayNameController.text.trim();
        final displayName = rawDisplayName.isEmpty
            ? username
            : InputValidator.normalizeDisplayName(rawDisplayName);

        final displayNameError = InputValidator.displayNameError(displayName);
        if (displayNameError != null) {
          setState(() => _error = displayNameError);
          _playSound(RainSoundEffect.error);
          return;
        }

        await ref
            .read(identityProvider.notifier)
            .register(
              username: username,
              displayName: displayName,
              password: password,
              gender: _gender,
            );
      } else {
        await ref
            .read(identityProvider.notifier)
            .login(username: username, password: password);
      }
      _playSound(RainSoundEffect.action);
    } catch (error) {
      setState(() => _error = _formatError(error));
      _playSound(RainSoundEffect.error);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _playSound(RainSoundEffect effect) {
    unawaited(ref.read(soundEffectsProvider).play(effect));
  }
}
