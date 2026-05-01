import '../../../core/services/hive_service.dart';

/// Persists settings in Hive settings box.
class SettingsService {
  /// Whether online sync is enabled.
  bool get isSyncEnabled =>
      HiveService.settingsBox.get('isSyncEnabled', defaultValue: false);

  /// Set sync enabled/disabled.
  Future<void> setSyncEnabled(bool value) async {
    await HiveService.settingsBox.put('isSyncEnabled', value);
  }

  /// Last successful sync time.
  DateTime? get lastSyncTime {
    final raw = HiveService.settingsBox.get('lastSyncTime');
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}
