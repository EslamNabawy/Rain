import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/connection_command/connection_command_models.dart';
import 'package:rain/presentation/widgets/connection_command_center.dart';

void main() {
  testWidgets('command center renders sections, modes, and sticky controls', (
    WidgetTester tester,
  ) async {
    final timeline =
        ConnectionTimeline.initial(
          peerId: 'bob',
          attemptId: 'run-1',
          policy: const ConnectionPolicy.defaults(),
        ).addStep(
          const ConnectionAttemptStep(
            layer: ConnectionLayer.webRtcDirect,
            state: ConnectionStepState.failed,
            userMessage: 'Direct path blocked.',
            startedAt: 1,
            endedAt: 2,
            failureCode: ConnectionFailureCode.directPathBlocked,
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConnectionCommandCenter(
              statusLabel: 'Failed',
              statusDetail: 'Direct path blocked.',
              statusColor: const Color(0xFFFF6B6B),
              statusIcon: Icons.error_outline,
              timeline: timeline,
              initialPolicy: const ConnectionPolicy.defaults(),
              diagnosticItems: const <ConnectionDiagnosticItem>[
                ConnectionDiagnosticItem(label: 'Route', value: 'Unknown'),
              ],
              canConnect: true,
              canRetry: true,
              canCancel: true,
              canDisconnect: true,
              canRunRelayProbe: true,
              onClose: () {},
              onConnect: (_) {},
              onRetry: (_) {},
              onCancel: () {},
              onDisconnect: () {},
              onRunRelayProbe: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Command Center'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Mode Selector'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Controls'), findsOneWidget);
    expect(find.text('Advanced Diagnostics'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('WebRTC Auto'), findsOneWidget);
    expect(find.text('WebRTC Direct'), findsOneWidget);
    expect(find.text('WebRTC Relay'), findsOneWidget);
    expect(find.text('Iroh Fallback'), findsOneWidget);
    expect(find.text('Iroh Direct'), findsNothing);
    expect(find.text('Iroh Relay'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Test Relay'), findsOneWidget);
  });

  testWidgets('command center advanced diagnostics fit narrow mobile width', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionCommandCenter(
            statusLabel: 'Connecting',
            statusDetail: 'Detecting route...',
            statusColor: const Color(0xFFFBBF24),
            statusIcon: Icons.sync,
            timeline: null,
            initialPolicy: const ConnectionPolicy.defaults(),
            diagnosticItems: const <ConnectionDiagnosticItem>[
              ConnectionDiagnosticItem(label: 'Selected pair', value: null),
              ConnectionDiagnosticItem(label: 'Relay protocol', value: ''),
            ],
            canConnect: false,
            canRetry: false,
            canCancel: true,
            canDisconnect: false,
            canRunRelayProbe: false,
            onClose: () {},
            onConnect: (_) {},
            onRetry: (_) {},
            onCancel: () {},
            onDisconnect: () {},
            onRunRelayProbe: () {},
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Advanced Diagnostics'));
    await tester.tap(find.text('Advanced Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Unknown'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
