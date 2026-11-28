import 'package:farm_app/features/auth/providers/auth_provider.dart';
import 'package:farm_app/features/market/screens/market_screen.dart';
import 'package:farm_app/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _TestAuth extends ChangeNotifier implements AuthProvider {
  @override
  final user = LocalUser(
    id: 'local-a',
    email: 'farmer@example.test',
    firebaseUid: 'firebase-a',
    passwordHash: '',
    salt: '',
  );

  int attempts = 0;

  @override
  Future<void> signInForMarket(String password) async {
    attempts++;
    throw Exception('Could not sign in. Check your password and try again.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Market follows the active Firebase identity and resets its tabs',
    (tester) async {
      final auth = _TestAuth();

      Future<void> showMarket(String? firebaseUid) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: Provider<String?>.value(
              value: firebaseUid,
              child: const MaterialApp(home: MarketScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await showMarket(null);
      expect(find.text('Sign in to use Market'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'test-password');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(auth.attempts, 1);
      expect(find.textContaining('Check your password'), findsOneWidget);

      await showMarket('firebase-a');
      expect(
        find.textContaining('Farmer discovery').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('My Shop'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Seller profiles').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Buying and selling').hitTestable(),
        findsOneWidget,
      );

      await showMarket('firebase-b');
      expect(find.text('Orders'), findsNothing);
      expect(find.text('Sign in to use Market'), findsOneWidget);
      await showMarket('firebase-a');
      expect(
        find.textContaining('Farmer discovery').hitTestable(),
        findsOneWidget,
      );
    },
  );
}
