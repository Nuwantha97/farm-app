import 'package:farm_app/features/auth/providers/auth_provider.dart';
import 'package:farm_app/features/market/screens/market_screen.dart';
import 'package:farm_app/features/market/widgets/sri_lanka_map.dart';
import 'package:farm_app/models/user_model.dart';
import 'package:flutter/services.dart';
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
  testWidgets('A shared pickup pin shows its farmer count and opens on tap', (
    tester,
  ) async {
    var selected = false;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SriLankaMap(
              pins: [
                MarketMapPin(
                  latitude: 7.87,
                  longitude: 80.65,
                  label: 'Fixture town',
                  count: 2,
                  onTap: () => selected = true,
                ),
              ],
            ),
          ),
        ),
      );
      await rootBundle.loadString('assets/maps/sri_lanka.json');
    });
    await tester.pumpAndSettle();
    final pin = find.byTooltip('Fixture town · 2 farmers');
    expect(pin.hitTestable(), findsOneWidget);
    await tester.tap(pin);
    expect(selected, isTrue);
  });

  testWidgets('Market opens Explore only for a matching Firebase identity', (
    tester,
  ) async {
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
      find.widgetWithText(OutlinedButton, 'Choose district').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('My Shop'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);

    await showMarket('firebase-b');
    expect(find.text('Orders'), findsNothing);
    expect(find.text('Sign in to use Market'), findsOneWidget);
    await showMarket('firebase-a');
    expect(
      find.widgetWithText(OutlinedButton, 'Choose district').hitTestable(),
      findsOneWidget,
    );
  });
}
