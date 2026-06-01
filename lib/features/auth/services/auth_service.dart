import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/hive_service.dart';
import '../../../models/user_model.dart';

/// Offline-first authentication service.
///
/// Registration: requires internet (writes to both Hive + Firebase Auth).
/// Login: checks Hive first (offline-capable), optionally verifies with Firebase.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const _uuid = Uuid();

  // ── Password hashing ────────────────────────────────────────

  /// Generate a random 32-character salt.
  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Hash password with SHA-256 + salt.
  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode('$password$salt');
    return sha256.convert(bytes).toString();
  }

  // ── Internet check ──────────────────────────────────────────

  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  // ── Registration (requires internet) ────────────────────────

  /// Register a new user.
  /// Saves to BOTH Firebase Auth and Hive.
  /// Throws if no internet connection.
  Future<LocalUser> register(String email, String password) async {
    // 1. Check internet connectivity
    if (!await _isOnline()) {
      throw Exception('Internet connection required to create account');
    }

    // 2. Create Firebase Auth account
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final firebaseUid = credential.user!.uid;

    // 3. Hash password for local storage
    final salt = _generateSalt();
    final passwordHash = _hashPassword(password, salt);

    // 4. Create local user
    final localUser = LocalUser(
      id: _uuid.v4(),
      email: email.toLowerCase().trim(),
      passwordHash: passwordHash,
      salt: salt,
      firebaseUid: firebaseUid,
    );

    // 5. Save to Hive
    await HiveService.usersBox.put(
      localUser.email,
      Map<String, dynamic>.from(localUser.toMap()),
    );

    debugPrint('AuthService: Registered user ${localUser.email} '
        '(local: ${localUser.id}, firebase: $firebaseUid)');

    return localUser;
  }

  // ── Login (offline-capable) ─────────────────────────────────

  /// Login with email and password.
  /// Checks Hive first (works offline).
  /// If sync enabled + online, also verifies with Firebase Auth.
  /// If user not in Hive but exists in Firebase, creates local entry.
  Future<LocalUser> login(String email, String password,
      {bool syncEnabled = false}) async {
    final normalizedEmail = email.toLowerCase().trim();

    // 1. Try local (Hive) authentication
    final localData = HiveService.usersBox.get(normalizedEmail);

    if (localData != null) {
      final localUser =
          LocalUser.fromMap(Map<String, dynamic>.from(localData));
      final hash = _hashPassword(password, localUser.salt);

      if (hash == localUser.passwordHash) {
        debugPrint('AuthService: Local login successful for $normalizedEmail');

        // If sync enabled + online, verify with Firebase too
        if (syncEnabled && await _isOnline()) {
          try {
            await _auth.signInWithEmailAndPassword(
              email: normalizedEmail,
              password: password,
            );
            debugPrint('AuthService: Firebase verification successful');
          } catch (e) {
            debugPrint('AuthService: Firebase verification failed: $e');
            // Still allow local login — Firebase might be out of sync
          }
        }

        return localUser;
      } else {
        throw Exception('Incorrect password');
      }
    }

    // 2. User not in Hive — try Firebase Auth (first login on this device)
    if (!await _isOnline()) {
      throw Exception('No account found. Internet required for first login.');
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final firebaseUid = credential.user!.uid;

      // Create local user entry
      final salt = _generateSalt();
      final passwordHash = _hashPassword(password, salt);

      final localUser = LocalUser(
        id: _uuid.v4(),
        email: normalizedEmail,
        passwordHash: passwordHash,
        salt: salt,
        firebaseUid: firebaseUid,
      );

      await HiveService.usersBox.put(
        normalizedEmail,
        Map<String, dynamic>.from(localUser.toMap()),
      );

      debugPrint('AuthService: Firebase login + local user created '
          'for $normalizedEmail');

      return localUser;
    } on FirebaseAuthException catch (e) {
      throw Exception(_getErrorMessage(e.code));
    }
  }

  // ── Logout ──────────────────────────────────────────────────

  Future<void> logout({bool syncEnabled = false}) async {
    if (syncEnabled) {
      try {
        await _auth.signOut();
      } catch (e) {
        debugPrint('AuthService: Firebase signOut failed: $e');
      }
    }
  }

  // ── Account deletion (requires internet) ────────────────────

  /// Delete user account from both Hive and Firebase.
  /// Requires internet to ensure Firebase data is cleaned up.
  Future<void> deleteAccount(String email, String password) async {
    if (!await _isOnline()) {
      throw Exception(
          'Internet connection required to delete account');
    }

    final normalizedEmail = email.toLowerCase().trim();

    // Re-authenticate with Firebase and delete
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      await credential.user!.delete();
    } catch (e) {
      debugPrint('AuthService: Firebase account deletion failed: $e');
      // Still proceed with local deletion
    }

    // Clear all local data
    await HiveService.clearAllData();

    debugPrint('AuthService: Account deleted for $normalizedEmail');
  }

  // ── Session restore ─────────────────────────────────────────

  /// Try to restore session from Hive settings.
  LocalUser? restoreSession() {
    final lastEmail = HiveService.settingsBox.get('lastLoggedInEmail');
    if (lastEmail == null) return null;

    final localData = HiveService.usersBox.get(lastEmail);
    if (localData == null) return null;

    return LocalUser.fromMap(Map<String, dynamic>.from(localData));
  }

  /// Save the current session email.
  Future<void> saveSession(String email) async {
    await HiveService.settingsBox.put('lastLoggedInEmail', email);
  }

  /// Clear the current session.
  Future<void> clearSession() async {
    await HiveService.settingsBox.delete('lastLoggedInEmail');
  }

  // ── Error messages ──────────────────────────────────────────

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'An account already exists with this email';
      case 'weak-password':
        return 'Password is too weak';
      case 'invalid-email':
        return 'Invalid email address';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      default:
        return 'Authentication failed. Please try again';
    }
  }
}
