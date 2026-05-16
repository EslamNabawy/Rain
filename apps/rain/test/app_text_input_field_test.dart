import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/widgets/app_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppTextInputField requests focus and accepts typed text', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextInputField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            labelText: 'Message',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'hello rain');
    expect(controller.text, 'hello rain');
  });
}
