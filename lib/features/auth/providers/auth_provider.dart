import 'package:flutter/material.dart';
import '../../../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  LocalUser? _user;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  LocalUser? get user => _user;
  bool get isAuthenticated => _user != null;
  String? get currentUserId => _user?.id;
  String? get firebaseUid => _user?.firebaseUid;

  AuthProvider() {
    // Try to restore session from Hive on app start
    _user = _authService.restoreSession();
  }

  Future<bool> login(String email, String password,
      {bool syncEnabled = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.login(
        email,
        password,
        syncEnabled: syncEnabled,
      );
      await _authService.saveSession(email.toLowerCase().trim());
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.register(email, password);
      await _authService.saveSession(email.toLowerCase().trim());
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout({bool syncEnabled = false}) async {
    await _authService.logout(syncEnabled: syncEnabled);
    await _authService.clearSession();
    _user = null;
    notifyListeners();
  }

  Future<bool> deleteAccount(String password) async {
    if (_user == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.deleteAccount(_user!.email, password);
      await _authService.clearSession();
      _user = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
