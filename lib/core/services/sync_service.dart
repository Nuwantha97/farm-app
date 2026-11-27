import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../features/finance/services/expense_service.dart';
import '../../models/crop_model.dart';
import '../../models/expense_model.dart';
import 'hive_service.dart';
import 'history_clear_service.dart';

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
      final userId = _getLocalUserId(firebaseUid);
      if (userId != null) {
        await HistoryClearService.synchronize(
          userId,
          _db.collection('users').doc(firebaseUid),
          () => _canSync(firebaseUid),
        );
      }
      for (final sync in [
        _syncCrops,
        _syncExpenses,
        _syncCommonExpenseHistory,
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
    final userId = _getLocalUserId(uid);
    final archive =
        box == HiveService.cropHistoryBox ||
        box == HiveService.expenseHistoryBox ||
        box == HiveService.commonExpenseHistoryBox;
    for (final doc in snapshot.docs) {
      if (!_canSync(uid)) return changes;
      if (doc.metadata.hasPendingWrites) continue;
      if (userId != null &&
          (archive ||
              box == HiveService.cropsBox &&
                  HistoryClearService.isArchived(doc.data())) &&
          HistoryClearService.isCleared(
            doc.data(),
            HistoryClearService.cutoff(userId),
          )) {
        continue;
      }
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
      if (HiveService.commonExpenseHistoryBox.containsKey(entry.key)) continue;

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
          final docRef = commonRef.doc(expense.localId);
          await docRef.set(expense.toMap());
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

  Future<SyncResult> _syncCommonExpenseHistory(String uid) async {
    final userId = _getLocalUserId(uid);
    if (userId == null) return SyncResult(errors: ['No local user found']);
    final account = _db.collection('users').doc(uid);
    final currentRef = account.collection('common_expenses');
    final archiveRef = account
        .collection('history')
        .doc('archive')
        .collection('common_expenses_history');
    final history = HiveService.commonExpenseHistoryBox;
    final current = HiveService.commonExpensesBox;
    var pushed = 0;
    var pulled = 0;
    final errors = <String>[];

    try {
      pulled = await _pull(
        uid,
        archiveRef,
        history,
        '${userId}_common_',
        _decodeExpenseHistory,
        removeMissing: false,
      );
    } catch (error) {
      errors.add('Common expense history pull error: $error');
    }

    for (final entry in HiveService.getItemsByUser(history, userId)) {
      if (!_canSync(uid)) break;
      final data = entry.value;
      if (HistoryClearService.isCleared(
        data,
        HistoryClearService.cutoff(userId),
      )) {
        continue;
      }
      if (data['syncStatus'] == 'synced' && !current.containsKey(entry.key)) {
        continue;
      }
      try {
        final expense = Expense.fromMap(Map<String, dynamic>.from(data));
        final activeId = current.get(entry.key)?['firebaseId'] as String?;
        final originalId =
            activeId ??
            data['originalFirebaseId'] as String? ??
            expense.firebaseId;
        if (data['syncStatus'] != 'synced') {
          final batch = _db.batch();
          batch.set(archiveRef.doc(expense.localId), {
            ..._encodeExpenseHistory(data, expense),
            'originalFirebaseId': originalId,
          });
          batch.delete(currentRef.doc(originalId ?? expense.localId));
          await batch.commit();
          if (!_canSync(uid)) break;
          await history.put(entry.key, {
            ...data,
            'syncStatus': 'synced',
            'originalFirebaseId': originalId,
          });
          pushed++;
        }
        if (_canSync(uid)) await current.delete(entry.key);
      } catch (error) {
        errors.add('Common expense archive error: $error');
      }
    }
    return SyncResult(pushed: pushed, pulled: pulled, errors: errors);
  }

  Map<String, dynamic> _encodeExpenseHistory(Map data, Expense expense) => {
    ...expense.toMap(),
    'archivedAt': Timestamp.fromDate(
      DateTime.tryParse(data['archivedAt']?.toString() ?? '') ??
          expense.updatedAt,
    ),
  };

  Map<String, dynamic> _decodeExpenseHistory(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) => {
    ...Expense.fromFirestore(doc).toHiveMap(),
    'archivedAt': (doc.data()['archivedAt'] as Timestamp?)
        ?.toDate()
        .toIso8601String(),
    'originalFirebaseId': doc.data()['originalFirebaseId'],
    'historySynced': true,
  };

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

    final archive = userRef.collection('history').doc('archive');
    final archivedCrops = await archive.collection('crops_history').get();
    for (final crop in archivedCrops.docs) {
      final expenses = await crop.reference
          .collection('expenses_history')
          .get();
      for (final expense in expenses.docs) {
        await expense.reference.delete();
      }
      await crop.reference.delete();
    }
    final archivedCommon = await archive
        .collection('common_expenses_history')
        .get();
    for (final expense in archivedCommon.docs) {
      await expense.reference.delete();
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

    final account = _db.collection('users').doc(firebaseUid);
    final legacyRef = account.collection('crop_history');
    final historyRef = account
        .collection('history')
        .doc('archive')
        .collection('crops_history');
    final crops = HiveService.cropHistoryBox;
    final expenses = HiveService.expenseHistoryBox;
    final userPrefix = '${userId}_';

    for (final collection in [legacyRef, historyRef]) {
      try {
        pulled += await _pull(
          firebaseUid,
          collection,
          crops,
          userPrefix,
          (doc) => {
            ...Crop.fromFirestore(doc).copyWith(isArchived: true).toHiveMap(),
            'historySynced': collection == historyRef,
          },
          removeMissing: false,
        );
      } catch (error) {
        errors.add('Crop history pull error: $error');
      }
    }

    // Older clients could archive the current crop before uploading its history.
    for (final entry in HiveService.getItemsByUser(
      HiveService.cropsBox,
      userId,
    )) {
      if (!_canSync(firebaseUid)) break;
      final data = entry.value;
      if (data['syncStatus'] == 'deleted' ||
          (data['isArchived'] != true && data['archivedAt'] == null) ||
          crops.containsKey(entry.key)) {
        continue;
      }
      await crops.put(entry.key, {
        ...data,
        'firebaseId': null,
        'syncStatus': 'pending',
      });
    }

    for (final entry in HiveService.getItemsByUser(crops, userId)) {
      if (!_canSync(firebaseUid)) break;
      final data = Map<String, dynamic>.from(entry.value);
      final cropId = entry.key.substring(userPrefix.length);
      if (HistoryClearService.isCleared(
        data,
        HistoryClearService.cutoff(userId),
      )) {
        continue;
      }
      final document = historyRef.doc(cropId);
      final expenseRef = document.collection('expenses_history');
      final current = HiveService.cropsBox.get(entry.key);
      final cropPrefix = '${userId}_${cropId}_';
      final originalCropId = current?['firebaseId'];
      final legacyPrefix = originalCropId is String
          ? '${userId}_${originalCropId}_'
          : cropPrefix;

      try {
        if (data['syncStatus'] == 'deleted') continue;
        if (data['historySynced'] != true) {
          final crop = Crop.fromMap({...data, 'localId': cropId});
          await document.set(crop.copyWith(isArchived: true).toMap());
          if (!_canSync(firebaseUid)) break;
          final latest = crops.get(entry.key);
          if (_sameVersion(latest, data)) {
            await crops.put(entry.key, {
              ...latest!,
              'syncStatus': 'synced',
              'historySynced': true,
            });
          }
          pushed++;
        }

        pulled += await _pull(
          firebaseUid,
          expenseRef,
          expenses,
          cropPrefix,
          (doc) => {
            ..._decodeExpenseHistory(doc),
            'cropId': cropId,
            'cropName': data['name'],
          },
          legacyPrefix: legacyPrefix,
          removeMissing: false,
        );
        if (!_canSync(firebaseUid)) break;
        await ExpenseService.snapshotCropExpenses(
          userId,
          cropId,
          {...?current, 'name': data['name']},
          (data['archivedAt'] ??
                  data['updatedAt'] ??
                  DateTime.now().toIso8601String())
              .toString(),
        );

        final pending = <String, MapEntry<String, Map>>{};
        for (final expenseEntry in HiveService.getItemsByUser(
          expenses,
          userId,
        )) {
          final key = expenseEntry.key;
          if (!key.startsWith(cropPrefix) && !key.startsWith(legacyPrefix)) {
            continue;
          }
          final snapshot = expenseEntry.value;
          if (snapshot['syncStatus'] == 'deleted') continue;
          final prefix = key.startsWith(cropPrefix) ? cropPrefix : legacyPrefix;
          final id =
              (snapshot['localId'] ??
                      snapshot['id'] ??
                      key.substring(prefix.length))
                  .toString();
          if (!pending.containsKey(id) || key.startsWith(cropPrefix)) {
            pending[id] = expenseEntry;
          }
        }
        for (final item in pending.entries) {
          if (!_canSync(firebaseUid)) break;
          final snapshot = item.value.value;
          if (snapshot['historySynced'] == true) continue;
          final expense = Expense.fromMap({
            ...snapshot,
            'localId': item.key,
            'cropId': cropId,
            'cropName': data['name'],
          });
          await expenseRef
              .doc(item.key)
              .set(
                _encodeExpenseHistory({
                  ...snapshot,
                  'archivedAt': snapshot['archivedAt'] ?? data['archivedAt'],
                }, expense),
              );
          if (_canSync(firebaseUid) && expenses.containsKey(item.value.key)) {
            await expenses.put(item.value.key, {
              ...snapshot,
              'historySynced': true,
            });
          }
          pushed++;
        }
      } catch (error) {
        errors.add('Crop history sync error: $error');
      }
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
    );
  }
}
