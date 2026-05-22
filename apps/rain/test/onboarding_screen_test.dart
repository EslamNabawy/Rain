import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain/presentation/screens/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('username input lowercases capital letters before filtering', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: OnboardingScreen())),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'ALICE_1');

    final editable = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(editable.controller.text, 'alice_1');
  });

  testWidgets('focused credential field stays above the mobile keyboard', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: true,
            body: OnboardingScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final passwordField = _textFieldWithLabel('Password');
    await tester.tap(passwordField);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final keyboardTop =
        tester.view.physicalSize.height - tester.view.viewInsets.bottom;
    expect(tester.getRect(passwordField).bottom, lessThan(keyboardTop - 64));
    expect(tester.getRect(passwordField).top, lessThan(220));
  });

  testWidgets('login credential fields use matching geometry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: OnboardingScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final usernameRect = tester.getRect(_textFieldWithLabel('Username'));
    final passwordRect = tester.getRect(_textFieldWithLabel('Password'));

    expect(usernameRect.height, moreOrLessEquals(passwordRect.height));
    expect(usernameRect.left, moreOrLessEquals(passwordRect.left));
    expect(usernameRect.right, moreOrLessEquals(passwordRect.right));
  });
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (Widget widget) =>
        widget is TextField && widget.decoration?.labelText == label,
  );
}
