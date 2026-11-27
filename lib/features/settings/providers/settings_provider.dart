import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../../../core/services/sync_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsService _settingsService = SettingsService();
  final SyncService _syncService = SyncService();

  bool _isSyncing = false;
  bool _isResetting = false;
  String? _syncError;
  SyncResult? _lastSyncResult;

  bool get isSyncEnabled => _settingsService.isSyncEnabled;
  DateTime? get lastSyncTime => _settingsService.lastSyncTime;
  bool get isSyncing => _isSyncing;
  bool get isResetting => _isResetting;
  String? get syncError => _syncError;
  SyncResult? get lastSyncResult => _lastSyncResult;

  /// Toggle online sync on/off.
  /// When enabling, triggers an initial sync.
  Future<void> toggleSync(bool value, AuthProvider authProvider) async {
    if (_isResetting) return;
    await _settingsService.setSyncEnabled(value);
    notifyListeners();

    if (value && authProvider.firebaseUid != null) {
      // Trigger initial sync when enabling
      await syncNow(authProvider);
    }
  }

  /// Manually trigger a full bidirectional sync.
  Future<void> syncNow(AuthProvider authProvider) async {
    if (_isSyncing || _isResetting || !isSyncEnabled) return;
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

  Future<String?> resetFarmData(AuthProvider auth) async {
    if (_isResetting) return 'A farm reset is already in progress.';
    final localId = auth.currentUserId;
    final uid = auth.firebaseUid;
    if (localId == null || uid == null) {
      return 'Sign in with cloud sync enabled to reset farm data.';
    }
    _isResetting = true;
    notifyListeners();
    try {
      await _syncService.resetFarmData(localId, uid);
      _syncError = null;
      _lastSyncResult = null;
      return null;
    } on StateError catch (error) {
      return error.message;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return 'Firestore denied the reset. Check that the updated rules are deployed.';
      }
      return error.message ?? 'Could not finish the reset. Try again.';
    } catch (error) {
      debugPrint('Farm reset could not finish: $error');
      return 'Could not confirm the reset. Check your connection and try again.';
    } finally {
      _isResetting = false;
      notifyListeners();
    }
  }

  /// Clear sync error message.
  void clearError() {
    _syncError = null;
    notifyListeners();
  }
}
