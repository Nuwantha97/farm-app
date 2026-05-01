import 'package:flutter/material.dart';

import '../../../core/services/hive_service.dart';
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
    if (_isSyncing) return;
    if (authProvider.firebaseUid == null) {
      _syncError = 'No Firebase account linked';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      // Check if this is a first-time sync (no local data but has Firebase data)
      final localCrops =
          HiveService.getItemsByUser(HiveService.cropsBox, authProvider.currentUserId!);
      if (localCrops.isEmpty) {
        // Initial pull for existing Firebase users
        await _syncService.initialPull(authProvider.firebaseUid!);
      }

      _lastSyncResult =
          await _syncService.fullSync(authProvider.firebaseUid!);

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
