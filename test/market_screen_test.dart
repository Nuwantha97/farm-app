import 'dart:async';

import 'package:farm_app/features/auth/providers/auth_provider.dart';
import 'package:farm_app/features/market/screens/market_screen.dart';
import 'package:farm_app/features/market/widgets/sri_lanka_map.dart';
import 'package:farm_app/features/market/widgets/market_live_builder.dart';
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
  testWidgets(
    'Market listeners restart on return and clear when accounts change',
    (tester) async {
      final auth = _TestAuth();
      final uid = ValueNotifier<String?>('firebase-a');
      final visible = ValueNotifier(true);
      final navigator = GlobalKey<NavigatorState>();
      final subscriptions = <StreamController<String>>[];
      var cancelled = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: ValueListenableBuilder<String?>(
            valueListenable: uid,
            builder: (context, value, child) =>
                Provider<String?>.value(value: value, child: child!),
            child: MaterialApp(
              navigatorKey: navigator,
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (context, value, child) =>
                      MarketVisibility(visible: value, child: child!),
                  child: MarketLiveBuilder<String>(
                    firebaseUid: 'firebase-a',
                    stream: () {
                      final controller = StreamController<String>(
                        sync: true,
                        onCancel: () => cancelled++,
                      );
                      subscriptions.add(controller);
                      return controller.stream;
                    },
                    builder: (context, snapshot) =>
                        Text(snapshot.data ?? 'Loading'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(subscriptions, hasLength(1));
      subscriptions.last.add('Original result');
      await tester.pump();
      expect(find.text('Original result'), findsOneWidget);
      visible.value = false;
      await tester.pump();
      expect(cancelled, 1);
      visible.value = true;
      await tester.pump();
      expect(subscriptions, hasLength(2));
      subscriptions.last.add('Updated result');
      await tester.pumpAndSettle();
      expect(find.text('Updated result'), findsOneWidget);

      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Details')),
        ),
      );
      await tester.pumpAndSettle();
      expect(cancelled, 2);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(subscriptions, hasLength(3));
      uid.value = 'firebase-b';
      await tester.pump();
      expect(cancelled, 3);
      expect(find.text('Updated result'), findsNothing);
      expect(
        find.textContaining('Sign in with the same account'),
        findsOneWidget,
      );
      for (final controller in subscriptions) {
        unawaited(controller.close());
      }
      await tester.pumpWidget(const SizedBox.shrink());
      uid.dispose();
      visible.dispose();
    },
  );

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
