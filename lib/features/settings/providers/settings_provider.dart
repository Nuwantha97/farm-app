import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;

import '../../../core/services/sync_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsService _settingsService = SettingsService();
  final SyncService _syncService = SyncService();

  bool _isSyncing = false;
  String? _syncError;
  SyncResult? _lastSyncResult;

  bool get isSyncEnabled => _settingsService.isSyncEnabled;
  DateTime? get lastSyncTime => _settingsService.lastSyncTime;
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;
  SyncResult? get lastSyncResult => _lastSyncResult;

  /// Toggle online sync on/off.
  /// When enabling, triggers an initial sync.
  Future<void> toggleSync(bool value, AuthProvider authProvider) async {
    await _settingsService.setSyncEnabled(value);
    notifyListeners();

    if (value && authProvider.firebaseUid != null) {
      // Trigger initial sync when enabling
      await syncNow(authProvider);
    }
  }

  /// Manually trigger a full bidirectional sync.
  Future<void> syncNow(AuthProvider authProvider) async {
    if (_isSyncing || !isSyncEnabled) return;
    final uid = authProvider.firebaseUid;
    if (uid == null) {
      _syncError = 'No Firebase account linked';
      notifyListeners();
      return;
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      _syncError = 'Sign out and sign in again with cloud sync enabled.';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      _lastSyncResult = await _syncService.fullSync(uid);

      if (_lastSyncResult!.hasErrors) {
        _syncError = _lastSyncResult!.errors.first;
      }
    } catch (e) {
      _syncError = 'Sync failed: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Clear sync error message.
  void clearError() {
    _syncError = null;
    notifyListeners();
  }
}
