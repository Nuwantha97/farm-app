import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';
import 'market_explore_screen.dart';
import 'market_orders_screen.dart';
import 'my_shop_screen.dart';

class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final firebaseUid = context.watch<String?>();
    final user = auth.user;
    if (user == null ||
        firebaseUid == null ||
        firebaseUid != user.firebaseUid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Market')),
        body: user == null
            ? const Center(
                child: Text('Sign in to your FarmApp account first.'),
              )
            : _MarketSignIn(
                key: ValueKey(user.id),
                email: user.email,
                signIn: auth.signInForMarket,
              ),
      );
    }

    return DefaultTabController(
      key: ValueKey(firebaseUid),
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Market'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Explore'),
              Tab(text: 'My Shop'),
              Tab(text: 'Orders'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            MarketExploreScreen(firebaseUid: firebaseUid),
            MyShopScreen(firebaseUid: firebaseUid),
            MarketOrdersScreen(firebaseUid: firebaseUid),
          ],
        ),
      ),
    );
  }
}

class _MarketSignIn extends StatefulWidget {
  const _MarketSignIn({super.key, required this.email, required this.signIn});

  final String email;
  final Future<void> Function(String password) signIn;

  @override
  State<_MarketSignIn> createState() => _MarketSignInState();
}

class _MarketSignInState extends State<_MarketSignIn> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await widget.signIn(_password.text);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Sign in to use Market',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text('Enter the FarmApp password for ${widget.email}.'),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          enabled: !_busy,
          decoration: InputDecoration(labelText: 'Password', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
      ],
    );
  }
}
