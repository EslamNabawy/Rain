import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:protocol_brain/protocol_brain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _appPackage = 'com.rainapp.rain';

Future<void> main(List<String> _) async {
  try {
    await runAndroidPresenceRefreshSmoke();
    stdout.writeln('ANDROID_PRESENCE_REFRESH_SMOKE=PASS');
  } catch (error, stackTrace) {
    stderr.writeln('ANDROID_PRESENCE_REFRESH_SMOKE=FAIL');
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    exit(exitCode);
  }
}

Future<void> runAndroidPresenceRefreshSmoke() async {
  final config = _SmokeConfig.fromEnvironment();
  final probe = _SupabasePresenceProbe(config);

  try {
    await probe.authenticate();
    await _requireAndroidDevice(config.serial);
    await _buildAndInstallApk(config);
    await _clearAppData(config.serial, _appPackage);
    await _launchApp(config.serial, _appPackage);

    await _waitUntil(
      () async {
        final identity = await probe.fetchIdentity(config.username);
        return identity != null && identity['online'] == true;
      },
      description: 'initial presence online',
      timeout: const Duration(minutes: 2),
      interval: const Duration(seconds: 2),
    );

    final initialHeartbeat = await _waitForHeartbeat(
      probe,
      config.username,
      timeout: const Duration(minutes: 2),
    );

    await _goHome(config.serial);

    final updatedHeartbeat = await _waitForHeartbeat(
      probe,
      config.username,
      minimumHeartbeat: initialHeartbeat + 1,
      timeout: config.heartbeatInterval + const Duration(seconds: 45),
    );

    stdout.writeln('SMOKE_DETAILS');
    stdout.writeln('  device=${config.serial ?? 'auto-selected'}');
    stdout.writeln('  username=${config.username}');
    stdout.writeln('  initialHeartbeat=$initialHeartbeat');
    stdout.writeln('  updatedHeartbeat=$updatedHeartbeat');
    stdout.writeln('  heartbeatIntervalSeconds=${config.heartbeatInterval.inSeconds}');
  } finally {
    await _forceStop(config.serial, _appPackage);
    await probe.dispose();
  }
}

Future<void> _buildAndInstallApk(_SmokeConfig config) async {
  final appRoot = _appRootDirectory();
  final flutterArgs = <String>[
    'build',
    'apk',
    '--debug',
    '--dart-define=RAIN_BACKEND=supabase',
    '--dart-define=RAIN_SMOKE_MODE=true',
    '--dart-define=RAIN_SMOKE_USERNAME=${config.username}',
    '--dart-define=RAIN_SMOKE_PASSWORD=${config.password}',
    '--dart-define=RAIN_SMOKE_DISPLAY_NAME=${config.displayName}',
    '--dart-define=RAIN_BACKGROUND_HEARTBEAT_SECONDS=${config.heartbeatInterval.inSeconds}',
    '--dart-define=SUPABASE_URL=${config.supabaseUrl}',
    '--dart-define=SUPABASE_ANON_KEY=${config.supabaseAnonKey}',
  ];

  final build = await Process.run(
    'flutter',
    flutterArgs,
    workingDirectory: appRoot.path,
  );
  stdout.write(build.stdout);
  stderr.write(build.stderr);
  if (build.exitCode != 0) {
    throw StateError('flutter build apk failed with exit code ${build.exitCode}');
  }

  final apkPath = File(
    '${appRoot.path}${Platform.pathSeparator}build${Platform.pathSeparator}app${Platform.pathSeparator}outputs${Platform.pathSeparator}flutter-apk${Platform.pathSeparator}app-debug.apk',
  );
  if (!apkPath.existsSync()) {
    throw StateError('Expected debug apk was not produced at ${apkPath.path}');
  }

  final install = await Process.run(
    'adb',
    <String>[
      if (config.serial != null) '-s',
      if (config.serial != null) config.serial!,
      'install',
      '-r',
      apkPath.path,
    ],
    workingDirectory: appRoot.path,
  );
  stdout.write(install.stdout);
  stderr.write(install.stderr);
  if (install.exitCode != 0) {
    throw StateError('adb install failed with exit code ${install.exitCode}');
  }
}

Directory _appRootDirectory() {
  final script = Platform.script;
  if (script.scheme == 'file') {
    return File.fromUri(script).parent.parent;
  }
  return Directory.current;
}

Future<void> _clearAppData(String? serial, String packageName) async {
  final result = await _adb(
    serial,
    <String>['shell', 'pm', 'clear', packageName],
  );
  if (result.trim() != 'Success') {
    throw StateError('adb pm clear failed: $result');
  }
}

Future<void> _forceStop(String? serial, String packageName) async {
  await _adb(serial, <String>['shell', 'am', 'force-stop', packageName]);
}

Future<void> _goHome(String? serial) async {
  await _adb(serial, <String>['shell', 'input', 'keyevent', '3']);
}

Future<void> _launchApp(String? serial, String packageName) async {
  final resolved = await _adb(
    serial,
    <String>['shell', 'cmd', 'package', 'resolve-activity', '--brief', packageName],
  );
  final activity = _parseResolvedActivity(resolved, packageName);
  await _adb(
    serial,
    <String>['shell', 'am', 'start', '-n', activity],
  );
}

Future<void> _requireAndroidDevice(String? serial) async {
  final devices = await Process.run('adb', <String>['devices']);
  if (devices.exitCode != 0) {
    throw StateError('adb devices failed: ${devices.stderr}');
  }
  final attached = LineSplitter.split(devices.stdout.toString())
      .where((String line) => line.endsWith('\tdevice'))
      .map((String line) => line.split('\t').first.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);

  if (serial != null && serial.isNotEmpty) {
    if (!attached.contains(serial)) {
      throw StateError('ADB_SERIAL=$serial is not attached. Connected devices: $attached');
    }
    return;
  }

  if (attached.isEmpty) {
    throw StateError('No attached Android device or emulator was found.');
  }
  if (attached.length > 1) {
    throw StateError(
      'Multiple attached devices found: $attached. Set ADB_SERIAL to choose one.',
    );
  }
}

abstract class _PresenceSmokeProbe {
  Future<void> authenticate();
  Future<Map<String, dynamic>?> fetchIdentity(String username);
  Future<void> dispose();
}

class _SupabasePresenceProbe implements _PresenceSmokeProbe {
  _SupabasePresenceProbe(this._config)
    : _client = SupabaseClient(
        _config.supabaseUrl,
        _config.supabaseAnonKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
          autoRefreshToken: false,
        ),
      );

  final _SmokeConfig _config;
  final SupabaseClient _client;

  @override
  Future<void> authenticate() async {
    for (final email in _config.loginEmails) {
      try {
        await _client.auth.signInWithPassword(
          email: email,
          password: _config.password,
        );
        return;
      } catch (_) {}
    }

    await _client.auth.signUp(
      email: _config.preferredSupabaseEmail,
      password: _config.password,
    );
    if (_client.auth.currentSession == null) {
      await _client.auth.signInWithPassword(
        email: _config.preferredSupabaseEmail,
        password: _config.password,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchIdentity(String username) async {
    final rows =
        (await _client.from('users').select().eq('username', username).limit(1))
            as List<dynamic>;
    if (rows.isEmpty) {
      return null;
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return <String, dynamic>{
      'username': row['username'],
      'uid': row['uid'],
      'displayName': row['display_name'],
      'gender': row['gender'],
      'registeredAt': row['registered_at'],
      'lastSeen': row['last_seen'],
      'lastHeartbeat': row['last_heartbeat'],
      'online': row['online'],
    };
  }

  @override
  Future<void> dispose() async {
    await _client.dispose();
  }
}

Future<int> _waitForHeartbeat(
  _PresenceSmokeProbe probe,
  String username, {
  int? minimumHeartbeat,
  required Duration timeout,
}) async {
  final started = DateTime.now();
  while (true) {
    final identity = await probe.fetchIdentity(username);
    if (identity != null) {
      final heartbeat = (identity['lastHeartbeat'] as num?)?.toInt() ?? 0;
      final online = identity['online'] as bool? ?? false;
      if (online && (minimumHeartbeat == null || heartbeat >= minimumHeartbeat)) {
        return heartbeat;
      }
    }

    if (DateTime.now().difference(started) > timeout) {
      throw TimeoutException(
        'Timed out waiting for heartbeat update for $username',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  required String description,
  required Duration timeout,
  required Duration interval,
}) async {
  final started = DateTime.now();
  while (true) {
    if (await predicate()) {
      return;
    }

    if (DateTime.now().difference(started) > timeout) {
      throw TimeoutException('Timed out waiting for $description');
    }
    await Future<void>.delayed(interval);
  }
}

Future<String> _adb(String? serial, List<String> args) async {
  final command = <String>[
    if (serial != null && serial.isNotEmpty) '-s',
    if (serial != null && serial.isNotEmpty) serial,
    ...args,
  ];
  final result = await Process.run('adb', command);
  if (result.exitCode != 0) {
    throw StateError(
      'adb ${args.join(' ')} failed with exit code ${result.exitCode}: ${result.stderr}',
    );
  }
  return result.stdout.toString().trim();
}

String _parseResolvedActivity(String output, String packageName) {
  final lines = LineSplitter.split(output)
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList(growable: false);
  for (final line in lines.reversed) {
    if (line.contains('/')) {
      return line;
    }
  }
  return '$packageName/.MainActivity';
}

class _SmokeConfig {
  const _SmokeConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.username,
    required this.password,
    required this.displayName,
    required this.heartbeatInterval,
    required this.serial,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String username;
  final String password;
  final String displayName;
  final Duration heartbeatInterval;
  final String? serial;

  String get preferredSupabaseEmail => supabasePreferredEmailFromUsername(
    username,
    projectUrl: supabaseUrl,
  );

  List<String> get loginEmails => supabaseLoginEmailsFromUsername(
    username,
    projectUrl: supabaseUrl,
  );

  factory _SmokeConfig.fromEnvironment() {
    final supabaseUrl = Platform.environment['SUPABASE_URL'] ?? '';
    final supabaseAnonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? '';
    final username = Platform.environment['RAIN_SMOKE_USERNAME'] ?? '';
    final password = Platform.environment['RAIN_SMOKE_PASSWORD'] ?? '';
    final displayName =
        Platform.environment['RAIN_SMOKE_DISPLAY_NAME'] ?? username;
    final heartbeatSeconds = int.tryParse(
          Platform.environment['RAIN_BACKGROUND_HEARTBEAT_SECONDS'] ?? '5',
        ) ??
        5;

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError('SUPABASE_URL and SUPABASE_ANON_KEY are required');
    }
    if (username.isEmpty || password.isEmpty) {
      throw StateError('RAIN_SMOKE_USERNAME and RAIN_SMOKE_PASSWORD are required');
    }

    return _SmokeConfig(
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      username: username,
      password: password,
      displayName: displayName.isEmpty ? username : displayName,
      heartbeatInterval: Duration(
        seconds: heartbeatSeconds > 0 ? heartbeatSeconds : 5,
      ),
      serial: Platform.environment['ADB_SERIAL'],
    );
  }
}
