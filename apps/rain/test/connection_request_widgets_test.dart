import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/connection_requests/connection_request_status_chip.dart';

void main() {
  group('outbound connection request status chip', () {
    testWidgets('outbound pending chip renders and cancel calls runtime', (
      WidgetTester tester,
    ) async {
      ConnectionRequestActionKind? tappedAction;

      await tester.pumpWidget(
        _host(
          ConnectionRequestStatusChip(
            surface: _surface(status: ConnectionRequestStatus.pending),
            onAction:
                (
                  ConnectionRequestSurfaceModel _,
                  ConnectionRequestActionModel action,
                ) async {
                  tappedAction = action.kind;
                },
          ),
        ),
      );

      expect(find.text('Connection request pending'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Waiting for @bob to accept.'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('connection-request-action-cr-1-cancel'),
        ),
      );
      await tester.pump();

      expect(tappedAction, ConnectionRequestActionKind.cancel);
    });

    testWidgets('outbound duplicate pending message renders', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ConnectionRequestStatusChip(
            surface: _surface(
              status: ConnectionRequestStatus.pending,
              feedback: const ConnectionRequestFeedbackModel(
                reasonCode: ConnectionRequestReasonCode.duplicatePendingRequest,
                message: 'Connection request already sent to @bob.',
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('Connection request already sent to @bob.'),
        findsOneWidget,
      );
    });

    testWidgets('outbound daily limit message renders', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ConnectionRequestStatusChip(
            surface: _surface(
              status: ConnectionRequestStatus.failed,
              feedback: const ConnectionRequestFeedbackModel(
                reasonCode: ConnectionRequestReasonCode.dailyLimitExceeded,
                message: 'Daily connection request limit reached.',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Connection request failed'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(
        find.text('Daily connection request limit reached.'),
        findsOneWidget,
      );
    });

    testWidgets('outbound cooldown retry-after renders', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ConnectionRequestStatusChip(
            surface: _surface(
              status: ConnectionRequestStatus.pending,
              feedback: const ConnectionRequestFeedbackModel(
                reasonCode: ConnectionRequestReasonCode.rateLimited,
                message: 'Connection requests are cooling down.',
                retryAfter: Duration(seconds: 12),
              ),
            ),
          ),
        ),
      );

      expect(
        find.text(
          'Connection requests are cooling down. Try again in 12 seconds.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('outbound disabled button exposes semantic reason', (
      WidgetTester tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          ConnectionRequestStatusChip(
            surface: _surface(
              status: ConnectionRequestStatus.pending,
              actions: const <ConnectionRequestActionModel>[
                ConnectionRequestActionModel(
                  kind: ConnectionRequestActionKind.cancel,
                  label: 'Cancel',
                  semanticLabel: 'Cancel connection request to @bob',
                  enabled: false,
                  tooltip: 'Cancel unavailable while request is syncing.',
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byTooltip('Cancel unavailable while request is syncing.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Cancel unavailable while request is syncing.'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('outbound terminal statuses render status text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: <Widget>[
              ConnectionRequestStatusChip(
                surface: _surface(status: ConnectionRequestStatus.seen),
              ),
              ConnectionRequestStatusChip(
                surface: _surface(
                  requestId: 'cr-2',
                  status: ConnectionRequestStatus.accepted,
                ),
              ),
              ConnectionRequestStatusChip(
                surface: _surface(
                  requestId: 'cr-3',
                  status: ConnectionRequestStatus.rejected,
                ),
              ),
              ConnectionRequestStatusChip(
                surface: _surface(
                  requestId: 'cr-4',
                  status: ConnectionRequestStatus.canceled,
                ),
              ),
              ConnectionRequestStatusChip(
                surface: _surface(
                  requestId: 'cr-5',
                  status: ConnectionRequestStatus.expired,
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Seen'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Canceled'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
    });
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: RainTheme.dark(),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: child,
        ),
      ),
    ),
  );
}

ConnectionRequestSurfaceModel _surface({
  String requestId = 'cr-1',
  required ConnectionRequestStatus status,
  ConnectionRequestFeedbackModel? feedback,
  List<ConnectionRequestActionModel>? actions,
}) {
  return ConnectionRequestSurfaceModel(
    requestId: requestId,
    peerId: 'bob',
    peerLabel: '@bob',
    direction: ConnectionRequestDirection.outbound,
    status: status,
    title: switch (status) {
      ConnectionRequestStatus.pending ||
      ConnectionRequestStatus.seen => 'Connection request pending',
      ConnectionRequestStatus.accepted => 'Connection request accepted',
      ConnectionRequestStatus.rejected => 'Connection request declined',
      ConnectionRequestStatus.canceled => 'Connection request canceled',
      ConnectionRequestStatus.expired => 'Connection request expired',
      ConnectionRequestStatus.failed => 'Connection request failed',
    },
    subtitle: switch (status) {
      ConnectionRequestStatus.pending => 'Waiting for @bob to accept.',
      ConnectionRequestStatus.seen => '@bob has seen your request.',
      ConnectionRequestStatus.accepted => 'The peer lane can be opened now.',
      ConnectionRequestStatus.rejected => '@bob declined the request.',
      ConnectionRequestStatus.canceled => 'This request was canceled.',
      ConnectionRequestStatus.expired => 'Send a new request if needed.',
      ConnectionRequestStatus.failed => 'The request could not be completed.',
    },
    actions:
        actions ??
        (status.isTerminal
            ? const <ConnectionRequestActionModel>[]
            : const <ConnectionRequestActionModel>[
                ConnectionRequestActionModel(
                  kind: ConnectionRequestActionKind.cancel,
                  label: 'Cancel',
                  semanticLabel: 'Cancel connection request to @bob',
                  enabled: true,
                ),
              ]),
    feedback: feedback,
  );
}
