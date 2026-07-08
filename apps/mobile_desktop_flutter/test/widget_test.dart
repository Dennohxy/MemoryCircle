import 'package:flutter_test/flutter_test.dart';
import 'package:memory_circle/app/memory_circle_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('auth screen shows the brand and sign-in form', (tester) async {
    await tester.pumpWidget(const MemoryCircleApp());
    await tester.pumpAndSettle();

    expect(find.text('Omoide no Wa'), findsOneWidget);
    expect(
      find.text('Shared memories, beautifully kept.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('switching to create account reveals the name field',
      (tester) async {
    await tester.pumpWidget(const MemoryCircleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();

    expect(find.text('Your name'), findsOneWidget);
    expect(
      find.text('Create an account to start your family\'s circle.'),
      findsOneWidget,
    );
  });

  testWidgets('a saved session skips the sign-in screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'memory_circle_token': 'saved-token',
      'memory_circle_user':
          '{"id": 1, "display_name": "Owner Otieno", "email": "owner@example.com"}',
    });

    await tester.pumpWidget(const MemoryCircleApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('My Memory Circles'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });
}
