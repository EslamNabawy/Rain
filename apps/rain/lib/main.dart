import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/bootstrap/app_bootstrap.dart';
import 'core/config/app_environment.dart';
import 'application/state/app_providers.dart';
import 'infrastructure/services/crash_diagnostics_service.dart';
import 'infrastructure/window/desktop_shell_controller.dart';
import 'presentation/screens/rain_app.dart';
import 'presentation/screens/splash_screen.dart';

Future<void> main() async {
  CrashDiagnosticsService? diagnostics;

  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      diagnostics = CrashDiagnosticsService.instance;
      await diagnostics!.initialize();
      diagnostics!.installGlobalHandlers();
      await DesktopShellController().initializeBeforeRunApp();
      await runRainApp(crashDiagnosticsService: diagnostics);
    },
    (Object error, StackTrace stackTrace) {
      diagnostics?.recordErrorSync(
        error,
        stackTrace,
        source: 'dart-zone',
        fatal: true,
      );
    },
  );
}

@visibleForTesting
Future<void> runRainApp({
  AppEnvironment? environment,
  AppBootstrapper? bootstrapper,
  CrashDiagnosticsService? crashDiagnosticsService,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    RainStartupApp(
      environment: environment ?? AppEnvironment.fromEnvironment(),
      bootstrapper: bootstrapper ?? AppBootstrapper(),
      crashDiagnosticsService: crashDiagnosticsService,
    ),
  );
}

@visibleForTesting
class RainStartupApp extends StatefulWidget {
  const RainStartupApp({
    required this.environment,
    required this.bootstrapper,
    this.crashDiagnosticsService,
    super.key,
  });

  final AppEnvironment environment;
  final AppBootstrapper bootstrapper;
  final CrashDiagnosticsService? crashDiagnosticsService;

  @override
  State<RainStartupApp> createState() => _RainStartupAppState();
}

class _RainStartupAppState extends State<RainStartupApp> {
  late Future<AppBootstrapState> _bootstrapFuture;
  Object? _loggedBootstrapError;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = widget.bootstrapper.bootstrap(widget.environment);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBootstrapState>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error!;
          _logBootstrapError(error, snapshot.stackTrace);
          return BootstrapFailureApp(error: error);
        }

        final bootstrap = snapshot.data;
        if (bootstrap == null) {
          return const MaterialApp(
            title: 'Rain',
            debugShowCheckedModeBanner: false,
            home: RainSplashScreen(),
          );
        }

        return ProviderScope(
          overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
          child: const RainApp(),
        );
      },
    );
  }

  void _logBootstrapError(Object error, StackTrace? stackTrace) {
    if (identical(_loggedBootstrapError, error)) {
      return;
    }
    _loggedBootstrapError = error;
    widget.crashDiagnosticsService?.recordErrorSync(
      error,
      stackTrace,
      source: 'bootstrap',
      fatal: true,
    );
    debugPrint('Rain bootstrap failed: $error');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

@visibleForTesting
class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rain',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: RainStartupFailureScreen(error: error),
    );
  }
}
