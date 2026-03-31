import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';

enum RainBackend { noop, firebase, supabase }

class AppEnvironment {
  const AppEnvironment({
    required this.backend,
    required this.iceServers,
    required this.forceUpdateUrl,
    required this.firebaseApiKey,
    required this.firebaseAppId,
    required this.firebaseMessagingSenderId,
    required this.firebaseProjectId,
    required this.firebaseDatabaseUrl,
    required this.firebaseStorageBucket,
    required this.firebaseAuthDomain,
    required this.firebaseMeasurementId,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  final RainBackend backend;
  final List<Map<String, dynamic>> iceServers;
  final String forceUpdateUrl;
  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseMessagingSenderId;
  final String firebaseProjectId;
  final String firebaseDatabaseUrl;
  final String firebaseStorageBucket;
  final String firebaseAuthDomain;
  final String firebaseMeasurementId;
  final String supabaseUrl;
  final String supabaseAnonKey;

  factory AppEnvironment.fromEnvironment() {
    final backend = switch (const String.fromEnvironment(
      'RAIN_BACKEND',
      defaultValue: 'noop',
    )) {
      'firebase' => RainBackend.firebase,
      'supabase' => RainBackend.supabase,
      _ => RainBackend.noop,
    };

    final rawIceServers = const String.fromEnvironment(
      'RAIN_ICE_SERVERS',
      defaultValue: '',
    );
    final iceServers = rawIceServers.isEmpty
        ? defaultIceServers
        : List<Map<String, dynamic>>.from(
            (jsonDecode(rawIceServers) as List<dynamic>).cast<Map<String, dynamic>>(),
          );

    return AppEnvironment(
      backend: backend,
      iceServers: iceServers,
      forceUpdateUrl: const String.fromEnvironment(
        'RAIN_UPDATE_URL',
        defaultValue: 'https://github.com/EslamNabawy/Rain/releases',
      ),
      firebaseApiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
      firebaseAppId: const String.fromEnvironment('FIREBASE_APP_ID'),
      firebaseMessagingSenderId: const String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
      ),
      firebaseProjectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      firebaseDatabaseUrl: const String.fromEnvironment('FIREBASE_DATABASE_URL'),
      firebaseStorageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      firebaseAuthDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      firebaseMeasurementId: const String.fromEnvironment(
        'FIREBASE_MEASUREMENT_ID',
      ),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  FirebaseOptions? get firebaseOptions {
    if (!isFirebaseConfigured) {
      return null;
    }
    return FirebaseOptions(
      apiKey: firebaseApiKey,
      appId: firebaseAppId,
      messagingSenderId: firebaseMessagingSenderId,
      projectId: firebaseProjectId,
      databaseURL: firebaseDatabaseUrl,
      storageBucket: firebaseStorageBucket.isEmpty ? null : firebaseStorageBucket,
      authDomain: firebaseAuthDomain.isEmpty ? null : firebaseAuthDomain,
      measurementId: firebaseMeasurementId.isEmpty ? null : firebaseMeasurementId,
    );
  }

  bool get isFirebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseDatabaseUrl.isNotEmpty;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get shouldUseFallbackAdapter {
    return switch (backend) {
      RainBackend.noop => true,
      RainBackend.firebase => !isFirebaseConfigured,
      RainBackend.supabase => !isSupabaseConfigured,
    };
  }

  String get backendLabel => switch (backend) {
    RainBackend.noop => 'Local Demo',
    RainBackend.firebase => 'Firebase',
    RainBackend.supabase => 'Supabase',
  };

  String get fallbackReason => switch (backend) {
    RainBackend.noop =>
      'Running with the local demo adapter. Identities, friends, and queues work locally, but peer signaling is disabled until you choose Firebase or Supabase.',
    RainBackend.firebase =>
      'Firebase is selected but the required FIREBASE dart-defines are missing, so Rain is using the local demo adapter.',
    RainBackend.supabase =>
      'Supabase is selected but SUPABASE_URL and SUPABASE_ANON_KEY are missing, so Rain is using the local demo adapter.',
  };
}

const defaultIceServers = <Map<String, dynamic>>[
  <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
  <String, dynamic>{
    'urls': 'turn:openrelay.metered.ca:80',
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
];
