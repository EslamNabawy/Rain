import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/state/file_transfer_view.dart';
import 'package:rain/presentation/screens/home_screen.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain_core/rain_core.dart';

FileTransferView _view(
  FileTransferState state, {
  int transferred = 0,
  FileTransferDirection direction = FileTransferDirection.outgoing,
  String? error,
}) {
  return FileTransferView(
    record: FileTransferRecord(
      id: 't1',
      peerId: 'bob',
      messageId: 'm1',
      direction: direction,
      fileName: 'notes.txt',
      fileSize: 1000,
      bytesTransferred: transferred,
      state: state,
      createdAt: 1,
      updatedAt: 1,
      error: error,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  FileTransferView view, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        theme: RainTheme.dark(),
        home: Scaffold(
          body: buildFileTransferBubbleForTest(transferView: view),
        ),
      ),
    ),
  );
}

LinearProgressIndicator _bar(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));

void main() {
  testWidgets('sending 40 percent shows a determinate bar', (tester) async {
    await _pump(tester, _view(FileTransferState.sending, transferred: 400));
    await tester.pumpAndSettle();
    expect(_bar(tester).value, closeTo(0.4, 0.001));
    expect(find.text('Sending 40%'), findsOneWidget);
  });

  testWidgets('progress glides to a new value', (tester) async {
    await _pump(tester, _view(FileTransferState.sending, transferred: 200));
    await tester.pumpAndSettle();
    await _pump(tester, _view(FileTransferState.sending, transferred: 800));
    await tester.pump(RainMotion.progressTween ~/ 2);
    final mid = _bar(tester).value!;
    expect(mid, greaterThan(0.2));
    expect(mid, lessThan(0.8));
    await tester.pumpAndSettle();
    expect(_bar(tester).value, closeTo(0.8, 0.001));
  });

  testWidgets('offered shows an indeterminate bar and waiting label', (
    tester,
  ) async {
    await _pump(tester, _view(FileTransferState.offered));
    expect(_bar(tester).value, isNull);
    expect(find.text('Waiting for peer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completed swaps in the check icon', (tester) async {
    await _pump(tester, _view(FileTransferState.sending, transferred: 900));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('rain-file-transfer-check')),
      findsNothing,
    );
    await _pump(tester, _view(FileTransferState.completed, transferred: 1000));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('rain-file-transfer-check')),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('failed shows friendly error text', (tester) async {
    await _pump(
      tester,
      _view(FileTransferState.failed, error: 'SocketException: lost #3'),
    );
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
  });

  testWidgets('reduced motion leaves no running animation', (tester) async {
    await _pump(
      tester,
      _view(FileTransferState.offered),
      disableAnimations: true,
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    await _pump(
      tester,
      _view(FileTransferState.sending, transferred: 500),
      disableAnimations: true,
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
