import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../services/live_farm_sync.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/crops/screens/crop_list_screen.dart';
import '../../features/finance/screens/finance_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/market/screens/market_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final _liveSync = LiveFarmSync();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthProvider>(context);
    _liveSync.bind(auth.currentUserId, auth.firebaseUid);
  }

  @override
  void dispose() {
    _liveSync.dispose();
    super.dispose();
  }

  final List<Widget> _screens = const [
    HomeScreen(),
    CropListScreen(),
    FinanceScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ..._screens,
          if (_currentIndex == _screens.length)
            StreamProvider<String?>(
              create: (_) => FirebaseAuth.instance.authStateChanges().map(
                    (user) => user?.uid,
                  ),
              initialData: FirebaseAuth.instance.currentUser?.uid,
              catchError: (_, _) => null,
              child: const MarketScreen(),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.eco_outlined),
              activeIcon: Icon(Icons.eco),
              label: 'Crops',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet),
              label: 'Finance',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              activeIcon: Icon(Icons.storefront),
              label: 'Market',
            ),
          ],
        ),
      ),
    );
  }
}
