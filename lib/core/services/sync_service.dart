import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

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
  static final _runs = <String, Future<SyncResult>>{};
  static final _lastPullTime = <String, DateTime>{};

  static bool get isEnabled =>
      HiveService.settingsBox.get('isSyncEnabled', defaultValue: false) == true;

  bool _canSync(String uid) =>
      isEnabled && FirebaseAuth.instance.currentUser?.uid == uid;

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
    if (!isEnabled) return;
    final firebaseUid = _getFirebaseUid(localUserId);
    if (firebaseUid == null) return;
    final lastPull = _lastPullTime[firebaseUid];
    if (_runs.containsKey(firebaseUid) ||
        (lastPull != null &&
            DateTime.now().difference(lastPull).inSeconds < 30)) {
      return;
    }

    final result = await fullSync(firebaseUid);
    if (!result.hasErrors) {
      _lastPullTime[firebaseUid] = DateTime.now();
    }
    debugPrint('SyncService: Background pull complete');
  }

  /// Immediate sync triggered after a CRUD operation or pull-to-refresh.
  ///
  /// Skips the 30-second cooldown but still respects the sync-enabled
  /// setting. Requests received during a sync share a follow-up run.
  Future<void> immediateSync(String localUserId) async {
    if (!isEnabled) return;
    final firebaseUid = _getFirebaseUid(localUserId);
    if (firebaseUid == null) return;
    final inProgress = _runs[firebaseUid];
    if (inProgress != null) await inProgress;
    if (!isEnabled || _getFirebaseUid(localUserId) != firebaseUid) return;

    final result = await fullSync(firebaseUid);
    if (!result.hasErrors) {
      _lastPullTime[firebaseUid] = DateTime.now();
    }
    debugPrint('SyncService: Immediate sync complete');
  }

  // ── Full bidirectional sync ─────────────────────────────────

  /// Perform a full bidirectional sync.
  Future<SyncResult> fullSync(String firebaseUid) => _runs.putIfAbsent(
    firebaseUid,
    () => _performSync(firebaseUid).whenComplete(() {
      _runs.remove(firebaseUid);
    }),
  );

  Future<SyncResult> _performSync(String firebaseUid) async {
    if (!isEnabled) return SyncResult();
    if (!_canSync(firebaseUid)) {
      return SyncResult(errors: ['Firebase sign-in required']);
    }

    if (!await isOnline()) {
      return SyncResult(errors: ['No internet connection']);
    }

    int pushed = 0;
    int pulled = 0;
    int conflicts = 0;
    final errors = <String>[];

    try {
      for (final sync in [
        _syncCrops,
        _syncExpenses,
        _syncCommonExpenses,
        _syncCropHistory,
      ]) {
        if (!_canSync(firebaseUid)) break;
        final result = await sync(firebaseUid);
        pushed += result.pushed;
        pulled += result.pulled;
        conflicts += result.conflicts;
        errors.addAll(result.errors);
      }

      // Update last sync time
      if (_canSync(firebaseUid) && errors.isEmpty) {
        await HiveService.settingsBox.put(
          'lastSyncTime',
          DateTime.now().toIso8601String(),
        );
      }

      debugPrint(
        'SyncService: Full sync complete — '
        'pushed: $pushed, pulled: $pulled, conflicts: $conflicts',
      );
    } catch (e) {
      errors.add('Sync failed: $e');
      debugPrint('SyncService: Sync error: $e');
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
    );
  }

  Future<int> _pull(
    String uid,
    CollectionReference<Map<String, dynamic>> collection,
    Box<Map> box,
    String prefix,
    Map<String, dynamic> Function(QueryDocumentSnapshot<Map<String, dynamic>>)
    decode, {
    String? legacyPrefix,
    bool removeMissing = true,
  }) async {
    if (!_canSync(uid)) return 0;
    final snapshot = await collection.get(
      const GetOptions(source: Source.server),
    );
    var changes = 0;
    for (final doc in snapshot.docs) {
      if (!_canSync(uid)) return changes;
      if (doc.metadata.hasPendingWrites) continue;
      final localId = doc.data()['localId'] ?? doc.id;
      final key = '$prefix$localId';
      final legacyKey = legacyPrefix == null ? null : '$legacyPrefix$localId';
      final storageKey =
          legacyKey != null &&
              !box.containsKey(key) &&
              box.containsKey(legacyKey)
          ? legacyKey
          : key;
      final local = box.get(storageKey);
      final remoteUpdated = (doc.data()['updatedAt'] as Timestamp?)?.toDate();
      final localUpdated = DateTime.tryParse(
        local?['updatedAt']?.toString() ?? '',
      );
      if (local == null ||
          (local['syncStatus'] == 'synced' &&
              remoteUpdated != null &&
              (localUpdated == null || remoteUpdated.isAfter(localUpdated)))) {
        await box.put(storageKey, decode(doc));
        changes++;
      }
    }

    if (!removeMissing ||
        snapshot.metadata.isFromCache ||
        snapshot.metadata.hasPendingWrites) {
      return changes;
    }
    final remoteIds = snapshot.docs.map((doc) => doc.id).toSet();
    for (final key in box.keys.whereType<String>().toList()) {
      if (!_canSync(uid)) break;
      if (!key.startsWith(prefix) &&
          (legacyPrefix == null || !key.startsWith(legacyPrefix))) {
        continue;
      }
      final local = box.get(key);
      final remoteId = local?['firebaseId'];
      if (local?['syncStatus'] == 'synced' &&
          remoteId is String &&
          !remoteIds.contains(remoteId)) {
        await box.delete(key);
        changes++;
      }
    }
    return changes;
  }

  bool _sameVersion(Map? current, Map original) =>
      current != null &&
      current['updatedAt'] == original['updatedAt'] &&
      current['syncStatus'] == original['syncStatus'];

  Future<void> _confirmUpload(
    String uid,
    Box<Map> box,
    Object key,
    Map original,
    String documentId,
  ) async {
    // Record the new document ID while preserving any edit made during upload.
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    final current = box.get(key);
    if (current == null) {
      await box.put(key, {
        ...original,
        'firebaseId': documentId,
        'syncStatus': 'deleted',
      });
      return;
    }
    await box.put(key, {
      ...current,
      'firebaseId': documentId,
      'syncStatus': _sameVersion(current, original)
          ? 'synced'
          : current['syncStatus'] == 'deleted'
          ? 'deleted'
          : 'modified',
    });
  }

  // ── Crops sync ──────────────────────────────────────────────

  Future<SyncResult> _syncCrops(String firebaseUid) async {
    int pushed = 0, pulled = 0, conflicts = 0;
    final errors = <String>[];

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return SyncResult(errors: ['No local user found']);

    final cropsRef = _db
        .collection('users')
        .doc(firebaseUid)
        .collection('crops');

    // 1. PUSH: Upload pending/modified local crops
    final localEntries = HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    );

    for (final entry in localEntries) {
      if (!_canSync(firebaseUid)) break;
      final data = Map<String, dynamic>.from(entry.value);
      final syncStatus = data['syncStatus'] ?? 'pending';

      try {
        if (syncStatus == 'deleted') {
          // Delete from Firebase
          final firebaseId = data['firebaseId'];
          if (firebaseId != null) {
            await cropsRef.doc(firebaseId).delete();
          }
          if (_sameVersion(HiveService.cropsBox.get(entry.key), data)) {
            await HiveService.cropsBox.delete(entry.key);
          }
          pushed++;
        } else if (syncStatus == 'pending' ||
            (syncStatus == 'modified' && data['firebaseId'] == null)) {
          // Create in Firebase
          final crop = Crop.fromMap(data);
          final docRef = await cropsRef.add(crop.toMap());
          // Update local with firebaseId
          await _confirmUpload(
            firebaseUid,
            HiveService.cropsBox,
            entry.key,
            data,
            docRef.id,
          );
          pushed++;
        } else if (syncStatus == 'modified') {
          final firebaseId = data['firebaseId'] as String?;
          if (firebaseId != null) {
            var documentId = firebaseId;
            // Check for conflict
            final remoteDoc = await cropsRef
                .doc(firebaseId)
                .get(const GetOptions(source: Source.server));
            if (!_canSync(firebaseUid)) break;
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
                if (_sameVersion(HiveService.cropsBox.get(entry.key), data)) {
                  await HiveService.cropsBox.put(entry.key, updated);
                }
                conflicts++;
                continue;
              }
            } else {
              // Remote deleted — re-create
              final crop = Crop.fromMap(data);
              final docRef = await cropsRef.add(crop.toMap());
              documentId = docRef.id;
            }
            await _confirmUpload(
              firebaseUid,
              HiveService.cropsBox,
              entry.key,
              data,
              documentId,
            );
            pushed++;
          }
        }
      } catch (e) {
        errors.add('Crop sync error (${data['name']}): $e');
      }
    }

    try {
      pulled += await _pull(
        firebaseUid,
        cropsRef,
        HiveService.cropsBox,
        '${userId}_',
        (doc) => Crop.fromFirestore(doc).toHiveMap(),
      );
    } catch (e) {
      errors.add('Crop pull error: $e');
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
    );
  }

  // ── Expenses sync ───────────────────────────────────────────

  Future<SyncResult> _syncExpenses(String firebaseUid) async {
    int pushed = 0, pulled = 0, conflicts = 0;
    final errors = <String>[];

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return SyncResult(errors: ['No local user found']);

    // Get all crop firebaseIds for mapping
    final cropsRef = _db
        .collection('users')
        .doc(firebaseUid)
        .collection('crops');

    final localCropEntries = HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    );

    for (final cropEntry in localCropEntries) {
      if (!_canSync(firebaseUid)) break;
      final cropData = Map<String, dynamic>.from(cropEntry.value);
      final cropFirebaseId = cropData['firebaseId'] as String?;
      final cropLocalId = cropData['localId'] ?? cropData['id'];
      if (cropFirebaseId == null) continue; // Crop not synced yet

      final expensesRef = cropsRef.doc(cropFirebaseId).collection('expenses');
      final expPrefix = '${userId}_${cropLocalId}_';
      final legacyPrefix = '${userId}_${cropFirebaseId}_';

      // PUSH local expenses
      for (final entry in HiveService.expensesBox.toMap().entries) {
        if (!_canSync(firebaseUid)) break;
        if (!entry.key.toString().startsWith(expPrefix) &&
            !entry.key.toString().startsWith(legacyPrefix)) {
          continue;
        }

        final data = Map<String, dynamic>.from(entry.value);
        final syncStatus = data['syncStatus'] ?? 'pending';

        try {
          if (syncStatus == 'deleted') {
            final fbId = data['firebaseId'];
            if (fbId != null) await expensesRef.doc(fbId).delete();
            if (_sameVersion(HiveService.expensesBox.get(entry.key), data)) {
              await HiveService.expensesBox.delete(entry.key);
            }
            pushed++;
          } else if (syncStatus == 'pending') {
            final expense = Expense.fromMap(data);
            final docRef = await expensesRef.add(expense.toMap());
            await _confirmUpload(
              firebaseUid,
              HiveService.expensesBox,
              entry.key,
              data,
              docRef.id,
            );
            pushed++;
          } else if (syncStatus == 'modified') {
            final fbId = data['firebaseId'];
            if (fbId != null) {
              final expense = Expense.fromMap(data);
              await expensesRef.doc(fbId).set(expense.toMap());
              await _confirmUpload(
                firebaseUid,
                HiveService.expensesBox,
                entry.key,
                data,
                fbId,
              );
              pushed++;
            }
          }
        } catch (e) {
          errors.add('Expense sync error: $e');
        }
      }

      try {
        pulled += await _pull(
          firebaseUid,
          expensesRef,
          HiveService.expensesBox,
          expPrefix,
          (doc) => Expense.fromFirestore(doc, cropId: cropLocalId).toHiveMap(),
          legacyPrefix: legacyPrefix,
        );
      } catch (e) {
        errors.add('Expense pull error: $e');
      }
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
    );
  }

  // ── Common expenses sync ────────────────────────────────────

  Future<SyncResult> _syncCommonExpenses(String firebaseUid) async {
    int pushed = 0, pulled = 0, conflicts = 0;
    final errors = <String>[];

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return SyncResult(errors: ['No local user found']);

    final commonRef = _db
        .collection('users')
        .doc(firebaseUid)
        .collection('common_expenses');
    final prefix = '${userId}_common_';

    // PUSH
    for (final entry in HiveService.commonExpensesBox.toMap().entries) {
      if (!_canSync(firebaseUid)) break;
      if (!entry.key.toString().startsWith(prefix)) continue;

      final data = Map<String, dynamic>.from(entry.value);
      final syncStatus = data['syncStatus'] ?? 'pending';

      try {
        if (syncStatus == 'deleted') {
          final fbId = data['firebaseId'];
          if (fbId != null) await commonRef.doc(fbId).delete();
          if (_sameVersion(
            HiveService.commonExpensesBox.get(entry.key),
            data,
          )) {
            await HiveService.commonExpensesBox.delete(entry.key);
          }
          pushed++;
        } else if (syncStatus == 'pending') {
          final expense = Expense.fromMap(data);
          final docRef = await commonRef.add(expense.toMap());
          await _confirmUpload(
            firebaseUid,
            HiveService.commonExpensesBox,
            entry.key,
            data,
            docRef.id,
          );
          pushed++;
        } else if (syncStatus == 'modified') {
          final fbId = data['firebaseId'];
          if (fbId != null) {
            final expense = Expense.fromMap(data);
            await commonRef.doc(fbId).set(expense.toMap());
            await _confirmUpload(
              firebaseUid,
              HiveService.commonExpensesBox,
              entry.key,
              data,
              fbId,
            );
            pushed++;
          }
        }
      } catch (e) {
        errors.add('Common expense sync error: $e');
      }
    }

    try {
      pulled += await _pull(
        firebaseUid,
        commonRef,
        HiveService.commonExpensesBox,
        prefix,
        (doc) => Expense.fromFirestore(doc).toHiveMap(),
      );
    } catch (e) {
      errors.add('Common expense pull error: $e');
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
    );
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

    // Delete crop history
    final historySnap = await userRef.collection('crop_history').get();
    for (final doc in historySnap.docs) {
      await doc.reference.delete();
    }

    // Delete user doc
    await userRef.delete();

    debugPrint('SyncService: Deleted all Firebase data for $firebaseUid');
  }

  // ── Crop history sync ───────────────────────────────────────

  Future<SyncResult> _syncCropHistory(String firebaseUid) async {
    int pushed = 0, pulled = 0, conflicts = 0;
    final errors = <String>[];

    final userId = _getLocalUserId(firebaseUid);
    if (userId == null) return SyncResult(errors: ['No local user found']);

    final historyRef = _db
        .collection('users')
        .doc(firebaseUid)
        .collection('crop_history');

    // PUSH: Upload local history entries
    final localEntries = HiveService.getItemsByUser(
      HiveService.cropHistoryBox,
      userId,
    );

    for (final entry in localEntries) {
      if (!_canSync(firebaseUid)) break;
      final data = Map<String, dynamic>.from(entry.value);
      final syncStatus = data['syncStatus'] ?? 'pending';
      final firebaseId = data['firebaseId'] as String?;

      try {
        if (syncStatus == 'deleted') {
          if (firebaseId != null) await historyRef.doc(firebaseId).delete();
          if (_sameVersion(HiveService.cropHistoryBox.get(entry.key), data)) {
            await HiveService.cropHistoryBox.delete(entry.key);
          }
          pushed++;
        } else if (syncStatus == 'pending' ||
            (syncStatus == 'modified' && firebaseId == null)) {
          // Create in Firebase
          final crop = Crop.fromMap(data);
          final docRef = await historyRef.add(crop.toMap());
          await _confirmUpload(
            firebaseUid,
            HiveService.cropHistoryBox,
            entry.key,
            data,
            docRef.id,
          );
          pushed++;
        } else if (syncStatus == 'modified' && firebaseId != null) {
          final crop = Crop.fromMap(data);
          await historyRef.doc(firebaseId).set(crop.toMap());
          await _confirmUpload(
            firebaseUid,
            HiveService.cropHistoryBox,
            entry.key,
            data,
            firebaseId,
          );
          pushed++;
        }
      } catch (e) {
        errors.add('History sync error: $e');
      }
    }

    try {
      pulled += await _pull(
        firebaseUid,
        historyRef,
        HiveService.cropHistoryBox,
        '${userId}_',
        (doc) => Crop.fromFirestore(doc).copyWith(isArchived: true).toHiveMap(),
        removeMissing: false,
      );
    } catch (e) {
      errors.add('History pull error: $e');
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
    );
  }
}
