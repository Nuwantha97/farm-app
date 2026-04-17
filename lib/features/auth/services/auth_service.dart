import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Current authenticated user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with email and password
  Future<User?> login(String email, String password) async {
    final res = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return res.user;
  }

  /// Register with email and password
  Future<User?> register(String email, String password) async {
    final res = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return res.user;
  }

  /// Sign out
  Future<void> logout() async {
    await _auth.signOut();
  }
}
