/// # main.dart
///
/// Entry point for the Rain Flutter application. Initializes Firebase, crash
/// diagnostics, performance profiling, and desktop shell before bootstrapping
/// the app via [AppBootstrapper] and running the root [RainApp] widget.
///
/// **Key types:** [main], [runRainApp]
///
/// **Depends on:** application bootstrap, crash diagnostics, presentation layer
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/bootstrap/app_bootstrap.dart';
import 'core/config/app_environment.dart';
import 'application/state/app_providers.dart';
import 'infrastructure/services/crash_diagnostics_service.dart';
import 'infrastructure/services/rain_debug_log_service.dart';
import 'infrastructure/window/desktop_shell_controller.dart';
import 'presentation/performance/rain_performance.dart';
import 'presentation/screens/rain_app.dart';
import 'presentation/screens/splash_screen.dart';

Future<void> main() async {
  CrashDiagnosticsService? diagnostics;

  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final environment = AppEnvironment.fromEnvironment();
      final performanceProfile = RainPerformanceProfile.detect();
      diagnostics = CrashDiagnosticsService.instance;
      await diagnostics!.initialize();
      diagnostics!.configureRuntimeDiagnostics(
        performanceProfile: performanceProfile.toJson(),
        captureFrameTimings: const bool.fromEnvironment(
          'RAIN_FRAME_DIAGNOSTICS',
        ),
      );
      diagnostics!.installGlobalHandlers();
      final debugLog = CrashDiagnosticsDebugLogService(
        diagnostics: diagnostics!,
        enabled: kDebugMode || environment.updateChannel == 'demo',
      );
      await DesktopShellController().initializeBeforeRunApp();
      await runRainApp(
        environment: environment,
        bootstrapper: AppBootstrapper(debugLogService: debugLog),
        crashDiagnosticsService: diagnostics,
        debugLogService: debugLog,
        performanceProfile: performanceProfile,
      );
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
  RainDebugLogService? debugLogService,
  RainPerformanceProfile? performanceProfile,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final effectiveEnvironment = environment ?? AppEnvironment.fromEnvironment();
  final effectiveCrashDiagnostics =
      crashDiagnosticsService ?? CrashDiagnosticsService.instance;
  final effectiveDebugLog =
      debugLogService ??
      CrashDiagnosticsDebugLogService(
        diagnostics: effectiveCrashDiagnostics,
        enabled: kDebugMode || effectiveEnvironment.updateChannel == 'demo',
      );

  runApp(
    RainStartupApp(
      environment: effectiveEnvironment,
      bootstrapper:
          bootstrapper ?? AppBootstrapper(debugLogService: effectiveDebugLog),
      crashDiagnosticsService: effectiveCrashDiagnostics,
      debugLogService: effectiveDebugLog,
      performanceProfile: performanceProfile ?? RainPerformanceProfile.detect(),
    ),
  );
}

@visibleForTesting
class RainStartupApp extends StatefulWidget {
  const RainStartupApp({
    required this.environment,
    required this.bootstrapper,
    required this.performanceProfile,
    this.crashDiagnosticsService,
    this.debugLogService,
    super.key,
  });

  final AppEnvironment environment;
  final AppBootstrapper bootstrapper;
  final RainPerformanceProfile performanceProfile;
  final CrashDiagnosticsService? crashDiagnosticsService;
  final RainDebugLogService? debugLogService;

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
    return RainPerformanceScope(
      profile: widget.performanceProfile,
      child: FutureBuilder<AppBootstrapState>(
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
            observers: widget.debugLogService == null
                ? const <ProviderObserver>[]
                : <ProviderObserver>[
                    RainDebugProviderObserver(widget.debugLogService!),
                  ],
            overrides: [
              appBootstrapProvider.overrideWithValue(bootstrap),
              if (widget.crashDiagnosticsService != null)
                crashDiagnosticsServiceProvider.overrideWithValue(
                  widget.crashDiagnosticsService!,
                ),
              if (widget.debugLogService != null)
                rainDebugLogServiceProvider.overrideWithValue(
                  widget.debugLogService!,
                ),
            ],
            child: const RainApp(),
          );
        },
      ),
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
