import 'package:flutter_test/flutter_test.dart';
import 'package:memory_circle/app/memory_circle_app.dart';

void main() {
  testWidgets('auth screen shows the brand and sign-in form', (tester) async {
    await tester.pumpWidget(const MemoryCircleApp());

    expect(find.text('Memory Circle'), findsOneWidget);
    expect(
      find.text('A quiet home for your family\'s photos and stories.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('switching to create account reveals the name field',
      (tester) async {
    await tester.pumpWidget(const MemoryCircleApp());

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();

    expect(find.text('Your name'), findsOneWidget);
    expect(
      find.text('Create an account to start your family\'s circle.'),
      findsOneWidget,
    );
  });
}
