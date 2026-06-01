import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Central Hive initialization and encrypted box management service.
///
/// All data boxes are encrypted with AES-256.
/// The encryption key is stored in the platform keychain via flutter_secure_storage.
class HiveService {
  static const _encryptionKeyName = 'farm_app_hive_encryption_key';

  static const String usersBoxName = 'users';
  static const String cropsBoxName = 'crops';
  static const String expensesBoxName = 'expenses';
  static const String commonExpensesBoxName = 'common_expenses';
  static const String settingsBoxName = 'settings';

  static late Box<Map> _usersBox;
  static late Box<Map> _cropsBox;
  static late Box<Map> _expensesBox;
  static late Box<Map> _commonExpensesBox;
  static late Box _settingsBox;

  /// Initialize Hive and open all encrypted boxes.
  /// Must be called before runApp() in main().
  static Future<void> init() async {
    await Hive.initFlutter();

    final encryptionKey = await _getOrCreateEncryptionKey();
    final cipher = HiveAesCipher(encryptionKey);

    _usersBox = await Hive.openBox<Map>(usersBoxName, encryptionCipher: cipher);
    _cropsBox = await Hive.openBox<Map>(cropsBoxName, encryptionCipher: cipher);
    _expensesBox =
        await Hive.openBox<Map>(expensesBoxName, encryptionCipher: cipher);
    _commonExpensesBox =
        await Hive.openBox<Map>(commonExpensesBoxName, encryptionCipher: cipher);
    _settingsBox =
        await Hive.openBox(settingsBoxName, encryptionCipher: cipher);
  }

  /// Get or create the AES-256 encryption key from secure storage.
  static Future<Uint8List> _getOrCreateEncryptionKey() async {
    const secureStorage = FlutterSecureStorage();
    final existingKey = await secureStorage.read(key: _encryptionKeyName);

    if (existingKey != null) {
      return base64Url.decode(existingKey);
    }

    // Generate a new 256-bit key
    final newKey = Hive.generateSecureKey();
    await secureStorage.write(
      key: _encryptionKeyName,
      value: base64UrlEncode(newKey),
    );
    return Uint8List.fromList(newKey);
  }

  // ── Box accessors ──────────────────────────────────────────────

  static Box<Map> get usersBox => _usersBox;
  static Box<Map> get cropsBox => _cropsBox;
  static Box<Map> get expensesBox => _expensesBox;
  static Box<Map> get commonExpensesBox => _commonExpensesBox;
  static Box get settingsBox => _settingsBox;

  // ── Data operations ────────────────────────────────────────────

  /// Clear all user data (for logout).
  /// Keeps the users box so the user can log back in offline.
  static Future<void> clearUserData() async {
    await _cropsBox.clear();
    await _expensesBox.clear();
    await _commonExpensesBox.clear();
    debugPrint('HiveService: Cleared all user data boxes');
  }

  /// Clear absolutely everything including user credentials (for account deletion).
  static Future<void> clearAllData() async {
    await _usersBox.clear();
    await _cropsBox.clear();
    await _expensesBox.clear();
    await _commonExpensesBox.clear();
    await _settingsBox.clear();
    debugPrint('HiveService: Cleared ALL data including user credentials');
  }

  /// Get all items from a box filtered by userId prefix in keys.
  static List<MapEntry<String, Map>> getItemsByUser(
    Box<Map> box,
    String userId,
  ) {
    final prefix = '${userId}_';
    return box.toMap().entries.where((e) {
      final key = e.key.toString();
      return key.startsWith(prefix);
    }).map((e) => MapEntry(e.key.toString(), Map<String, dynamic>.from(e.value))).toList();
  }
}
