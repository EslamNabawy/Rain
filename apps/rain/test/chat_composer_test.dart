import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_streak_surface.dart';
import 'package:rain/presentation/widgets/chat_composer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('send action submits trimmed text and keeps input focused', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    final sent = <String>[];

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            enabled: true,
            isSending: false,
            maxLength: 4000,
            onSend: () {
              sent.add(controller.text.trim());
              controller.clear();
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '  hello rain  ');
    expect(find.byType(RainStreakSurface), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, <String>['hello rain']);
    expect(controller.text, isEmpty);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('desktop enter sends and shift enter does not send', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    final sent = <String>[];

    addTearDown(controller.dispose);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatComposer(
              controller: controller,
              enabled: true,
              isSending: false,
              maxLength: 4000,
              onSend: () {
                sent.add(controller.text.trim());
                controller.clear();
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'first');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, <String>['first']);

      await tester.enterText(find.byType(TextField), 'second');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(sent, <String>['first']);
      expect(controller.text, 'second');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('attachment action is exposed separately from send', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    var attachCount = 0;
    var sendCount = 0;

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            enabled: true,
            isSending: false,
            maxLength: 4000,
            onAttach: () {
              attachCount += 1;
            },
            onSend: () {
              sendCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Attach file'));
    await tester.pump();

    expect(attachCount, 1);
    expect(sendCount, 0);
  });
}
