import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../models/crop_model.dart';
import '../../models/expense_model.dart';
import 'hive_service.dart';

/// Result of a sync operation.
class SyncResult {
  final int pushed;
  final int pulled;
  final int conflicts;
  final List<String> errors;

  SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
}

/// Bidirectional sync service between Hive (local) and Firebase (remote).
///
/// Strategy: Last-write-wins based on `updatedAt` timestamp.
/// Sync only runs when user has enabled sync AND internet is available.
class SyncService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static bool _isSyncing = false;
  static DateTime? _lastPullTime;

  /// Check internet connectivity.
  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Get firebaseUid from local userId by scanning the users box.
  String? _getFirebaseUid(String localUserId) {
    for (final entry in HiveService.usersBox.toMap().entries) {
      final data = Map<String, dynamic>.from(entry.value);
      if (data['id'] == localUserId) {
        return data['firebaseUid'] as String?;
      }
    }
    return null;
  }

  /// Background pull: fetch from Firebase and merge into Hive.
  ///
  /// Called by providers when loading data. Only runs if sync is
  /// enabled, internet is available, and not already syncing.
  /// Includes a 30-second cooldown to avoid excessive Firebase reads.
  Future<void> backgroundPull(String localUserId) async {
    if (_isSyncing) return;

    // Cooldown: don't pull more than once per 30 seconds
    if (_lastPullTime != null &&
        DateTime.now().difference(_lastPullTime!).inSeconds < 30) {
      return;
    }

    final isSyncEnabled =
        HiveService.settingsBox.get('isSyncEnabled', defaultValue: false);
    if (isSyncEnabled != true) return;

    final firebaseUid = _getFirebaseUid(localUserId);
    if (firebaseUid == null) return;

    final result = await fullSync(firebaseUid);
    if (!result.hasErrors) {
      _lastPullTime = DateTime.now();
    }
    debugPrint('SyncService: Background pull complete');
  }

  // ── Full bidirectional sync ─────────────────────────────────

  /// Perform a full bidirectional sync.
  Future<SyncResult> fullSync(String firebaseUid) async {
    if (_isSyncing) {
      return SyncResult();
    }

    if (!await isOnline()) {
      return SyncResult(errors: ['No internet connection']);
    }

    _isSyncing = true;
    int pushed = 0;
    int pulled = 0;
    int conflicts = 0;
    final errors = <String>[];

    try {
      // Sync crops
      final cropResult = await _syncCrops(firebaseUid);
      pushed += cropResult.pushed;
      pulled += cropResult.pulled;
      conflicts += cropResult.conflicts;
      errors.addAll(cropResult.errors);

      // Sync crop expenses
      final expResult = await _syncExpenses(firebaseUid);
      pushed += expResult.pushed;
      pulled += expResult.pulled;
      conflicts += expResult.conflicts;
      errors.addAll(expResult.errors);

      // Sync common expenses
      final commonResult = await _syncCommonExpenses(firebaseUid);
      pushed += commonResult.pushed;
      pulled += commonResult.pulled;
      conflicts += commonResult.conflicts;
      errors.addAll(commonResult.errors);

      // Update last sync time
      await HiveService.settingsBox
          .put('lastSyncTime', DateTime.now().toIso8601String());

      debugPrint('SyncService: Full sync complete — '
          'pushed: $pushed, pulled: $pulled, conflicts: $conflicts');
    } catch (e) {
      errors.add('Sync failed: $e');
      debugPrint('SyncService: Sync error: $e');
    } finally {
      _isSyncing = false;
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
    );
  }

  // ── Initial pull (for existing Firebase users) ──────────────

  /// Pull all data from Firebase for a user who has no local data yet.
  Future<void> initialPull(String firebaseUid) async {
    if (!await isOnline()) return;

    debugPrint('SyncService: Starting initial pull for $firebaseUid');

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return;

    // Pull crops
    final cropsSnap = await _db
        .collection('users')
        .doc(firebaseUid)
        .collection('crops')
        .get();

    for (final doc in cropsSnap.docs) {
      final crop = Crop.fromFirestore(doc);
      final key = '${userId}_${crop.localId}';
      if (!HiveService.cropsBox.containsKey(key)) {
        await HiveService.cropsBox.put(
          key,
          Map<String, dynamic>.from(crop.toHiveMap()),
        );

        // Pull expenses for this crop
        final expSnap = await doc.reference.collection('expenses').get();
        for (final expDoc in expSnap.docs) {
          final expense = Expense.fromFirestore(expDoc, cropId: doc.id);
          final expKey = '${userId}_${doc.id}_${expense.localId}';
          if (!HiveService.expensesBox.containsKey(expKey)) {
            await HiveService.expensesBox.put(
              expKey,
              Map<String, dynamic>.from(expense.toHiveMap()),
            );
          }
        }
      }
    }

    // Pull common expenses
    final commonSnap = await _db
        .collection('users')
        .doc(firebaseUid)
        .collection('common_expenses')
        .get();

    for (final doc in commonSnap.docs) {
      final expense = Expense.fromFirestore(doc);
      final key = '${userId}_common_${expense.localId}';
      if (!HiveService.commonExpensesBox.containsKey(key)) {
        await HiveService.commonExpensesBox.put(
          key,
          Map<String, dynamic>.from(expense.toHiveMap()),
        );
      }
    }

    await HiveService.settingsBox
        .put('lastSyncTime', DateTime.now().toIso8601String());

    debugPrint('SyncService: Initial pull complete — '
        '${cropsSnap.docs.length} crops, ${commonSnap.docs.length} common expenses');
  }

  // ── Crops sync ──────────────────────────────────────────────

  Future<SyncResult> _syncCrops(String firebaseUid) async {
    int pushed = 0, pulled = 0, conflicts = 0;
    final errors = <String>[];

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return SyncResult(errors: ['No local user found']);

    final cropsRef =
        _db.collection('users').doc(firebaseUid).collection('crops');

    // 1. PUSH: Upload pending/modified local crops
    final localEntries =
        HiveService.getItemsByUser(HiveService.cropsBox, userId);

    for (final entry in localEntries) {
      final data = Map<String, dynamic>.from(entry.value);
      final syncStatus = data['syncStatus'] ?? 'pending';

      try {
        if (syncStatus == 'deleted') {
          // Delete from Firebase
          final firebaseId = data['firebaseId'];
          if (firebaseId != null) {
            await cropsRef.doc(firebaseId).delete();
          }
          await HiveService.cropsBox.delete(entry.key);
          pushed++;
        } else if (syncStatus == 'pending') {
          // Create in Firebase
          final crop = Crop.fromMap(data);
          final docRef = await cropsRef.add(crop.toMap());
          // Update local with firebaseId
          data['firebaseId'] = docRef.id;
          data['syncStatus'] = 'synced';
          await HiveService.cropsBox
              .put(entry.key, Map<String, dynamic>.from(data));
          pushed++;
        } else if (syncStatus == 'modified') {
          final firebaseId = data['firebaseId'];
          if (firebaseId != null) {
            // Check for conflict
            final remoteDoc = await cropsRef.doc(firebaseId).get();
            if (remoteDoc.exists) {
              final remoteData = remoteDoc.data()!;
              final localUpdated = DateTime.parse(data['updatedAt']);
              final remoteUpdated = remoteData['updatedAt'] != null
                  ? (remoteData['updatedAt'] as Timestamp).toDate()
                  : DateTime(2000);

              if (localUpdated.isAfter(remoteUpdated) ||
                  localUpdated.isAtSameMomentAs(remoteUpdated)) {
                // Local wins
                final crop = Crop.fromMap(data);
                await cropsRef.doc(firebaseId).set(crop.toMap());
              } else {
                // Remote wins — update local
                final remoteCrop = Crop.fromFirestore(remoteDoc);
                final updated = remoteCrop.toHiveMap();
                updated['syncStatus'] = 'synced';
                await HiveService.cropsBox
                    .put(entry.key, Map<String, dynamic>.from(updated));
                conflicts++;
                continue;
              }
            } else {
              // Remote deleted — re-create
              final crop = Crop.fromMap(data);
              final docRef = await cropsRef.add(crop.toMap());
              data['firebaseId'] = docRef.id;
            }
            data['syncStatus'] = 'synced';
            await HiveService.cropsBox
                .put(entry.key, Map<String, dynamic>.from(data));
            pushed++;
          }
        }
      } catch (e) {
        errors.add('Crop sync error (${data['name']}): $e');
      }
    }

    // 2. PULL: Download new remote crops or update stale local copies
    try {
      final remoteSnap = await cropsRef.get();
      for (final doc in remoteSnap.docs) {
        final remoteData = doc.data();
        final remoteLocalId = remoteData['localId'] ?? doc.id;
        final localKey = '${userId}_$remoteLocalId';

        if (!HiveService.cropsBox.containsKey(localKey)) {
          // New remote item — pull it
          final crop = Crop.fromFirestore(doc);
          await HiveService.cropsBox.put(
            localKey,
            Map<String, dynamic>.from(crop.toHiveMap()),
          );
          pulled++;
        } else {
          // Existing item — update if remote is newer and local hasn't been modified
          final localData = Map<String, dynamic>.from(
              HiveService.cropsBox.get(localKey)!);
          final localSyncStatus = localData['syncStatus'] ?? 'synced';

          if (localSyncStatus == 'synced') {
            final localUpdated = localData['updatedAt'] != null
                ? DateTime.parse(localData['updatedAt'])
                : DateTime(2000);
            final remoteUpdated = remoteData['updatedAt'] != null
                ? (remoteData['updatedAt'] as Timestamp).toDate()
                : DateTime(2000);

            if (remoteUpdated.isAfter(localUpdated)) {
              final crop = Crop.fromFirestore(doc);
              await HiveService.cropsBox.put(
                localKey,
                Map<String, dynamic>.from(crop.toHiveMap()),
              );
              pulled++;
            }
          }
        }
      }
    } catch (e) {
      errors.add('Crop pull error: $e');
    }

    return SyncResult(
        pushed: pushed, pulled: pulled, conflicts: conflicts, errors: errors);
  }

  // ── Expenses sync ───────────────────────────────────────────

  Future<SyncResult> _syncExpenses(String firebaseUid) async {
    int pushed = 0, pulled = 0, conflicts = 0;
    final errors = <String>[];

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return SyncResult(errors: ['No local user found']);

    // Get all crop firebaseIds for mapping
    final cropsRef =
        _db.collection('users').doc(firebaseUid).collection('crops');

    final localCropEntries =
        HiveService.getItemsByUser(HiveService.cropsBox, userId);

    for (final cropEntry in localCropEntries) {
      final cropData = Map<String, dynamic>.from(cropEntry.value);
      final cropFirebaseId = cropData['firebaseId'] as String?;
      final cropLocalId = cropData['localId'] ?? cropData['id'];
      if (cropFirebaseId == null) continue; // Crop not synced yet

      final expensesRef =
          cropsRef.doc(cropFirebaseId).collection('expenses');
      final expPrefix = '${userId}_${cropLocalId}_';

      // PUSH local expenses
      for (final entry in HiveService.expensesBox.toMap().entries) {
        if (!entry.key.toString().startsWith(expPrefix)) continue;

        final data = Map<String, dynamic>.from(entry.value);
        final syncStatus = data['syncStatus'] ?? 'pending';

        try {
          if (syncStatus == 'deleted') {
            final fbId = data['firebaseId'];
            if (fbId != null) await expensesRef.doc(fbId).delete();
            await HiveService.expensesBox.delete(entry.key);
            pushed++;
          } else if (syncStatus == 'pending') {
            final expense = Expense.fromMap(data);
            final docRef = await expensesRef.add(expense.toMap());
            data['firebaseId'] = docRef.id;
            data['syncStatus'] = 'synced';
            await HiveService.expensesBox
                .put(entry.key, Map<String, dynamic>.from(data));
            pushed++;
          } else if (syncStatus == 'modified') {
            final fbId = data['firebaseId'];
            if (fbId != null) {
              final expense = Expense.fromMap(data);
              await expensesRef.doc(fbId).set(expense.toMap());
              data['syncStatus'] = 'synced';
              await HiveService.expensesBox
                  .put(entry.key, Map<String, dynamic>.from(data));
              pushed++;
            }
          }
        } catch (e) {
          errors.add('Expense sync error: $e');
        }
      }

      // PULL remote expenses (new + stale updates)
      try {
        final remoteSnap = await expensesRef.get();
        for (final doc in remoteSnap.docs) {
          final remoteData = doc.data();
          final remoteLocalId = remoteData['localId'] ?? doc.id;
          final localKey = '${userId}_${cropLocalId}_$remoteLocalId';

          if (!HiveService.expensesBox.containsKey(localKey)) {
            final expense =
                Expense.fromFirestore(doc, cropId: cropFirebaseId);
            await HiveService.expensesBox.put(
              localKey,
              Map<String, dynamic>.from(expense.toHiveMap()),
            );
            pulled++;
          } else {
            final localData = Map<String, dynamic>.from(
                HiveService.expensesBox.get(localKey)!);
            final localSyncStatus = localData['syncStatus'] ?? 'synced';

            if (localSyncStatus == 'synced') {
              final localUpdated = localData['updatedAt'] != null
                  ? DateTime.parse(localData['updatedAt'])
                  : DateTime(2000);
              final remoteUpdated = remoteData['updatedAt'] != null
                  ? (remoteData['updatedAt'] as Timestamp).toDate()
                  : DateTime(2000);

              if (remoteUpdated.isAfter(localUpdated)) {
                final expense =
                    Expense.fromFirestore(doc, cropId: cropFirebaseId);
                await HiveService.expensesBox.put(
                  localKey,
                  Map<String, dynamic>.from(expense.toHiveMap()),
                );
                pulled++;
              }
            }
          }
        }
      } catch (e) {
        errors.add('Expense pull error: $e');
      }
    }

    return SyncResult(
        pushed: pushed, pulled: pulled, conflicts: conflicts, errors: errors);
  }

  // ── Common expenses sync ────────────────────────────────────

  Future<SyncResult> _syncCommonExpenses(String firebaseUid) async {
    int pushed = 0, pulled = 0, conflicts = 0;
    final errors = <String>[];

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return SyncResult(errors: ['No local user found']);

    final commonRef =
        _db.collection('users').doc(firebaseUid).collection('common_expenses');
    final prefix = '${userId}_common_';

    // PUSH
    for (final entry in HiveService.commonExpensesBox.toMap().entries) {
      if (!entry.key.toString().startsWith(prefix)) continue;

      final data = Map<String, dynamic>.from(entry.value);
      final syncStatus = data['syncStatus'] ?? 'pending';

      try {
        if (syncStatus == 'deleted') {
          final fbId = data['firebaseId'];
          if (fbId != null) await commonRef.doc(fbId).delete();
          await HiveService.commonExpensesBox.delete(entry.key);
          pushed++;
        } else if (syncStatus == 'pending') {
          final expense = Expense.fromMap(data);
          final docRef = await commonRef.add(expense.toMap());
          data['firebaseId'] = docRef.id;
          data['syncStatus'] = 'synced';
          await HiveService.commonExpensesBox
              .put(entry.key, Map<String, dynamic>.from(data));
          pushed++;
        } else if (syncStatus == 'modified') {
          final fbId = data['firebaseId'];
          if (fbId != null) {
            final expense = Expense.fromMap(data);
            await commonRef.doc(fbId).set(expense.toMap());
            data['syncStatus'] = 'synced';
            await HiveService.commonExpensesBox
                .put(entry.key, Map<String, dynamic>.from(data));
            pushed++;
          }
        }
      } catch (e) {
        errors.add('Common expense sync error: $e');
      }
    }

    // PULL (new + stale updates)
    try {
      final remoteSnap = await commonRef.get();
      for (final doc in remoteSnap.docs) {
        final remoteData = doc.data();
        final remoteLocalId = remoteData['localId'] ?? doc.id;
        final localKey = '${userId}_common_$remoteLocalId';

        if (!HiveService.commonExpensesBox.containsKey(localKey)) {
          final expense = Expense.fromFirestore(doc);
          await HiveService.commonExpensesBox.put(
            localKey,
            Map<String, dynamic>.from(expense.toHiveMap()),
          );
          pulled++;
        } else {
          final localData = Map<String, dynamic>.from(
              HiveService.commonExpensesBox.get(localKey)!);
          final localSyncStatus = localData['syncStatus'] ?? 'synced';

          if (localSyncStatus == 'synced') {
            final localUpdated = localData['updatedAt'] != null
                ? DateTime.parse(localData['updatedAt'])
                : DateTime(2000);
            final remoteUpdated = remoteData['updatedAt'] != null
                ? (remoteData['updatedAt'] as Timestamp).toDate()
                : DateTime(2000);

            if (remoteUpdated.isAfter(localUpdated)) {
              final expense = Expense.fromFirestore(doc);
              await HiveService.commonExpensesBox.put(
                localKey,
                Map<String, dynamic>.from(expense.toHiveMap()),
              );
              pulled++;
            }
          }
        }
      }
    } catch (e) {
      errors.add('Common expense pull error: $e');
    }

    return SyncResult(
        pushed: pushed, pulled: pulled, conflicts: conflicts, errors: errors);
  }

  // ── Helpers ─────────────────────────────────────────────────

  /// Get local userId from firebaseUid by scanning the users box.
  String? _getLocalUserId(String firebaseUid) {
    for (final entry in HiveService.usersBox.toMap().entries) {
      final data = Map<String, dynamic>.from(entry.value);
      if (data['firebaseUid'] == firebaseUid) {
        return data['id'];
      }
    }
    return null;
  }

  /// Delete all user data from Firebase (for account deletion).
  Future<void> deleteAllFirebaseData(String firebaseUid) async {
    if (!await isOnline()) return;

    final userRef = _db.collection('users').doc(firebaseUid);

    // Delete all crops and their sub-collections
    final cropsSnap = await userRef.collection('crops').get();
    for (final cropDoc in cropsSnap.docs) {
      final expSnap = await cropDoc.reference.collection('expenses').get();
      for (final expDoc in expSnap.docs) {
        await expDoc.reference.delete();
      }
      await cropDoc.reference.delete();
    }

    // Delete common expenses
    final commonSnap = await userRef.collection('common_expenses').get();
    for (final doc in commonSnap.docs) {
      await doc.reference.delete();
    }

    // Delete user doc
    await userRef.delete();

    debugPrint('SyncService: Deleted all Firebase data for $firebaseUid');
  }
}
